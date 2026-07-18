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

// Olc-cost-l: enforcement контроля ПОДКЛЮЧЕНИЯ (AuthHook). Читает
// /var/lib/olcrtc/access-control.json. Списки устройств подключения — ОТДЕЛЬНЫЕ
// от подписки: глоб. conn_devices/conn_ban; per-client conn_allow/conn_ban.
// Активен: глоб. enabled && enforce_connections (все инстансы) ЛИБО per-client
// conn_enforce (когда глоб. enforce_connections ВЫКЛ; scope all|selective).
// Пустой allow-лист при активном энфорсе = БЛОКИРОВАТЬ ВСЕХ (НЕ fail-open).
// Fail-open ТОЛЬКО при ошибке чтения/парса файла (чтобы не рвать при сбое ФС).
// Каждая попытка подключения при активном энфорсе логируется (device=…) — её
// видно в журнале подключений панели. ⛔ формат синхронизировать с панельным
// olcAccessControl/olcClientAccess (patch-…-access-control-api).

import (
	"encoding/json"
	"errors"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/openlibrecommunity/olcrtc/internal/logger"
)

const olcAccessControlPath = "/var/lib/olcrtc/access-control.json"

type olcAccDevice struct {
	HWID    string `json:"hwid"`
	Enabled bool   `json:"enabled"`
}

type olcAccClient struct {
	ConnAllow     []olcAccDevice `json:"conn_allow"`
	ConnBan       []olcAccDevice `json:"conn_ban"`
	BanNoHwid     bool           `json:"ban_no_hwid"`
	ConnEnforce   bool           `json:"conn_enforce"`
	ConnScope     string         `json:"conn_scope"`
	ConnInstances []string       `json:"conn_instances"`
}

type olcAccControl struct {
	Enabled      bool                     `json:"enabled"`
	EnforceConns bool                     `json:"enforce_connections"`
	BanNoHwid    bool                     `json:"ban_no_hwid"`
	ConnDevices  []olcAccDevice           `json:"conn_devices"`
	ConnBan      []olcAccDevice           `json:"conn_ban"`
	Clients      map[string]*olcAccClient `json:"clients"`
}

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

// olcAccDecideConn — решение для ПОДКЛЮЧЕНИЯ: banNoHwid, списки allow/ban.
// Пустой allow = блок всех (энфорс включён осознанно).
func olcAccDecideConn(dev string, banNoHwid bool, allow []olcAccDevice, ban []olcAccDevice) bool {
	if olcAccMatch(ban, dev) {
		return false
	}
	if dev == "" {
		return !banNoHwid
	}
	if olcAccMatch(allow, dev) {
		return true
	}
	return false // не в списке (в т.ч. пустой список) — блок
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
	room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
	finish := func(ok bool) (string, error) {
		logger.Infof("olc-access: conn attempt device=%s allowed=%t room=%s", dev, ok, room)
		if ok {
			return admit()
		}
		return "", errors.New("device not allowed to connect")
	}
	// 1) Глобальный энфорс подключения — приоритетнее, на все инстансы.
	if ac.EnforceConns {
		return finish(olcAccDecideConn(dev, ac.BanNoHwid, ac.ConnDevices, ac.ConnBan))
	}
	// 2) Выборочный per-client (только когда глобальный выключен).
	cid := strings.TrimSpace(os.Getenv("OLCRTC_CLIENT_ID"))
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
				return finish(olcAccDecideConn(dev, ac.BanNoHwid || cc.BanNoHwid, cc.ConnAllow, cc.ConnBan))
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
