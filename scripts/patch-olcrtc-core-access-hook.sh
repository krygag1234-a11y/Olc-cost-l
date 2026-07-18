#!/usr/bin/env bash
# Olc-cost-l olcrtc-core patch: enforcement контроля доступа НА ПОДКЛЮЧЕНИИ.
#
# olcrtc-core (internal/server) поддерживает Config.AuthHook (handshake.AuthFunc):
#   func(deviceID string, claims map[string]any) (sessionID string, err error)
# вызывается после CLIENT_HELLO; вернуть err = отклонить клиента (REJECT).
# По умолчанию cmd/olcrtc его НЕ ставит (admit-all defaultAuthHook).
#
# Этот патч добавляет olcAccessConnectionAuthHook, читающий тот же
# /var/lib/olcrtc/access-control.json, что и шлюз подписки. Закрывает сценарий
# «слили инстанс»: даже с валидными room_id/key чужое устройство не подключится.
#
# SAFE-BY-DEFAULT (критично — иначе можно оборвать ВСЕ туннели):
#   - энфорс НА ПОДКЛЮЧЕНИИ включается ТОЛЬКО при enabled=true И
#     enforce_connections=true (отдельный флаг, по умолчанию false);
#   - любая ошибка (нет файла/парс) → FAIL-OPEN (пускаем);
#   - пустой allowlist при включённом энфорсе → FAIL-OPEN + один лог-варн
#     (защита от самоблокировки);
#   - глобальный ban и ban_no_hwid учитываются.
# ⚠️ Требует теста с РЕАЛЬНЫМ устройством перед доверием (см. docs/ACCESS-CONTROL.md).
#
# Idempotent. Target: $OLCRTC_REPO. Run in apply_olcrtc (до go build ./cmd/olcrtc).
set -euo pipefail

OLCRTC_REPO="${1:?usage: $0 <olcrtc-repo-root>}"
SESSION_GO="$OLCRTC_REPO/internal/app/session/session.go"
HOOK_GO="$OLCRTC_REPO/internal/app/session/olc_access_hook.go"
[[ -f "$SESSION_GO" ]] || { echo "[patch-olcrtc-core-access-hook] ERROR: $SESSION_GO not found"; exit 1; }

# 1. Файл с реализацией хука (перезаписываем — источник истины здесь).
cat > "$HOOK_GO" <<'GO'
package session

// Olc-cost-l: enforcement контроля доступа на УРОВНЕ ПОДКЛЮЧЕНИЯ (AuthHook).
// Читает /var/lib/olcrtc/access-control.json (тот же файл, что шлюз подписки).
// SAFE-BY-DEFAULT: любая ошибка/пустой allowlist → пускаем (fail-open), чтобы не
// рвать туннели. Два независимых источника энфорса на подключении:
//   1) ГЛОБАЛЬНЫЙ: enabled && enforce_connections — на ВСЕ инстансы;
//   2) ВЫБОРОЧНЫЙ per-client: clients[cid].conn_enforce (действует ТОЛЬКО когда
//      глобальный enforce_connections ВЫКЛЮЧЕН) — scope "all"|"selective" (по
//      room_id из conn_instances). cid/room берутся из env OLCRTC_CLIENT_ID/
//      OLCRTC_ROOM_ID, которые менеджер прокидывает в процесс инстанса.
// ⛔ ПРАВИЛО РАЗРАБОТЧИКУ: при изменении формата access-control.json —
// синхронизируйте структуры ниже и панельный olcAccessControl/olcClientAccess.

import (
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync"

	"github.com/google/uuid"
	"github.com/openlibrecommunity/olcrtc/internal/logger"
)

const olcAccessControlPath = "/var/lib/olcrtc/access-control.json"

type olcAccDevice struct {
	HWID    string `json:"hwid"`
	Enabled bool   `json:"enabled"`
}

type olcAccClient struct {
	Mode          string         `json:"mode"`
	Allow         []olcAccDevice `json:"allow"`
	Ban           []olcAccDevice `json:"ban"`
	BanNoHwid     bool           `json:"ban_no_hwid"`
	ConnEnforce   bool           `json:"conn_enforce"`
	ConnScope     string         `json:"conn_scope"`
	ConnInstances []string       `json:"conn_instances"`
}

type olcAccControl struct {
	Enabled      bool                     `json:"enabled"`
	EnforceConns bool                     `json:"enforce_connections"`
	BanNoHwid    bool                     `json:"ban_no_hwid"`
	Devices      []olcAccDevice           `json:"devices"`
	Ban          []olcAccDevice           `json:"ban"`
	Clients      map[string]*olcAccClient `json:"clients"`
}

var olcAccWarnOnce sync.Once

func olcAccMatch(list []olcAccDevice, dev string) bool {
	for _, d := range list {
		if d.Enabled && strings.TrimSpace(d.HWID) != "" && strings.EqualFold(strings.TrimSpace(d.HWID), dev) {
			return true
		}
	}
	return false
}

func olcAccCount(lists ...[]olcAccDevice) int {
	n := 0
	for _, l := range lists {
		for _, d := range l {
			if d.Enabled && strings.TrimSpace(d.HWID) != "" {
				n++
			}
		}
	}
	return n
}

// olcAccDecide — общее решение: dev против списков allow/ban (уже собранных).
func olcAccDecide(dev string, banNoHwid bool, allow []olcAccDevice, ban []olcAccDevice, extraAllow []olcAccDevice, extraBan []olcAccDevice) (string, error) {
	admit := func() (string, error) { return uuid.NewString(), nil }
	if olcAccMatch(ban, dev) || olcAccMatch(extraBan, dev) {
		return "", errors.New("device banned")
	}
	if dev == "" {
		if banNoHwid {
			return "", errors.New("no device id")
		}
		return admit()
	}
	if olcAccMatch(allow, dev) || olcAccMatch(extraAllow, dev) {
		return admit()
	}
	if olcAccCount(allow, extraAllow) == 0 {
		olcAccWarnOnce.Do(func() {
			logger.Infof("olc-access: энфорс подключения включён, но allowlist пуст — пускаю всех (fail-open)")
		})
		return admit()
	}
	return "", errors.New("device not allowed")
}

func olcAccessConnectionAuthHook(deviceID string, _ map[string]any) (string, error) {
	admit := func() (string, error) { return uuid.NewString(), nil }
	data, err := os.ReadFile(olcAccessControlPath)
	if err != nil {
		return admit()
	}
	var ac olcAccControl
	if json.Unmarshal(data, &ac) != nil {
		return admit()
	}
	if !ac.Enabled {
		return admit()
	}
	dev := strings.TrimSpace(deviceID)
	// 1) Глобальный энфорс подключения — приоритетнее, действует на все инстансы.
	if ac.EnforceConns {
		return olcAccDecide(dev, ac.BanNoHwid, ac.Devices, ac.Ban, nil, nil)
	}
	// 2) Выборочный per-client (только когда глобальный выключен).
	cid := strings.TrimSpace(os.Getenv("OLCRTC_CLIENT_ID"))
	room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
	if cid != "" && ac.Clients != nil {
		if cc, ok := ac.Clients[cid]; ok && cc != nil && cc.ConnEnforce {
			enforced := true
			if cc.ConnScope == "selective" {
				enforced = false
				for _, r := range cc.ConnInstances {
					if strings.TrimSpace(r) == room && room != "" {
						enforced = true
						break
					}
				}
			}
			if enforced {
				return olcAccDecide(dev, ac.BanNoHwid || cc.BanNoHwid, ac.Devices, ac.Ban, cc.Allow, cc.Ban)
			}
		}
	}
	return admit()
}
GO
echo "[patch-olcrtc-core-access-hook] wrote $HOOK_GO"

# 2. Вставить AuthHook в server.Config литерал (перед OnSessionOpen).
python3 - "$SESSION_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
if 'AuthHook:         olcAccessConnectionAuthHook,' in t or 'AuthHook: olcAccessConnectionAuthHook,' in t:
    print("[patch-olcrtc-core-access-hook] AuthHook already wired")
    sys.exit(0)
anchor = '\t\t\tOnSessionOpen: func(sessionID, deviceID string, claims map[string]any) {'
repl = '\t\t\tAuthHook:         olcAccessConnectionAuthHook,\n' + anchor
if anchor in t:
    t = t.replace(anchor, repl, 1)
    f.write_text(t)
    print("[patch-olcrtc-core-access-hook] wired AuthHook into server.Config")
else:
    print("[patch-olcrtc-core-access-hook] WARN: OnSessionOpen anchor not found — hook file present but not wired")
PY
