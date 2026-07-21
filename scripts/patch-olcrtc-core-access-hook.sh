#!/usr/bin/env bash
# Olc-cost-l olcrtc-core patch: enforcement контроля доступа НА ПОДКЛЮЧЕНИИ
# + ban-watcher (непрерывный энфорс на ЖИВЫХ сессиях, точечный кик девайса).
#
# Часть 1 — AuthHook (handshake): olcrtc-core (internal/server) поддерживает
# Config.AuthHook (handshake.AuthFunc): вызывается после CLIENT_HELLO; вернуть
# err = отклонить клиента (REJECT). По умолчанию cmd/olcrtc его НЕ ставит.
# Хук читает тот же /var/lib/olcrtc/access-control.json, что и шлюз подписки.
#
# Часть 2 — ban-watcher (internal/server/olc_ban_watcher.go, сессия №18):
# горутина на Server, каждые 2с пере-проверяет ЖИВЫЕ сессии тем же решением,
# что и handshake (server.OlcBanRecheck, ставится из init() хука). Забаненный
# девайс кикается ТОЧЕЧНО: per-peer сессия → removePeerSession («banned», клиенту
# уходит control CLOSE — olcbox видит разрыв), singleton → reinstallSession
# (сброс sessionID → клиент обязан пройти handshake заново → REJECT).
# Остальные девайсы инстанса НЕ страдают (раньше менеджер РЕСТАРТОВАЛ инстанс
# целиком). Закрывает и класс «утёкшая сессия» (редкий fail-open на handshake —
# watcher добьёт за ≤2с).
#
# SAFE-BY-DEFAULT:
#   - любая ошибка чтения/парса файла → FAIL-OPEN (пускаем/не кикаем), но теперь
#     С WARN-ЛОГОМ (throttle 30с; тихий fail-open скрывал причины — сессия №18);
#     отсутствие файла (ENOENT) — норма, без лога;
#   - бан-лист действует ВСЕГДА (даже в «Выключено», сессия №17); энфорс-вайтлист
#     — только при conn_enforce/enforce_connections;
#   - пустой allowlist при включённом энфорсе = блок всех (осознанно);
#   - watcher не активен, пока не открылась хоть одна сессия (ленивый старт).
# ⚠️ Требует теста с РЕАЛЬНЫМ устройством (см. docs/ACCESS-CONTROL.md).
#
# Idempotent. Target: $OLCRTC_REPO. Run in apply_olcrtc (до go build ./cmd/olcrtc).
set -euo pipefail

OLCRTC_REPO="${1:?usage: $0 <olcrtc-repo-root>}"
SESSION_GO="$OLCRTC_REPO/internal/app/session/session.go"
SERVER_GO="$OLCRTC_REPO/internal/server/server.go"
HOOK_GO="$OLCRTC_REPO/internal/app/session/olc_access_hook.go"
WATCHER_GO="$OLCRTC_REPO/internal/server/olc_ban_watcher.go"
[[ -f "$SESSION_GO" ]] || { echo "[patch-olcrtc-core-access-hook] ERROR: $SESSION_GO not found"; exit 1; }
[[ -f "$SERVER_GO" ]] || { echo "[patch-olcrtc-core-access-hook] ERROR: $SERVER_GO not found"; exit 1; }

# 1. Файл с реализацией хука (перезаписываем — источник истины здесь).
cat > "$HOOK_GO" <<'GO'
package session

// Olc-cost-l: enforcement контроля ПОДКЛЮЧЕНИЯ (AuthHook + recheck для
// ban-watcher). Читает /var/lib/olcrtc/access-control.json. Списки устройств
// подключения — ОТДЕЛЬНЫЕ от подписки: глоб. conn_devices/conn_ban; per-client
// conn_allow/conn_ban.
// Энфорс (вайтлист): глоб. enabled && enforce_connections (все инстансы) ЛИБО
// per-client conn_enforce (когда глоб. контроль ВЫКЛ; scope all|selective).
// БАН-ЛИСТ подключения действует ВСЕГДА (даже при выключенном энфорсе —
// «Выключено (пускать всех, кроме бан-листа)», сессия №17).
// Пустой allow-лист при активном энфорсе = БЛОКИРОВАТЬ ВСЕХ (НЕ fail-open).
// Fail-open ТОЛЬКО при ошибке чтения/парса файла — теперь с WARN-логом
// (throttle 30с): тихий fail-open маскировал редкие «утёкшие» сессии (№18).
// init() регистрирует то же решение в server.OlcBanRecheck — ban-watcher
// применяет его к ЖИВЫМ сессиям каждые 2с (точечный кик забаненного девайса).
// ⛔ формат синхронизировать с панельным olcAccessControl/olcClientAccess
// (patch-…-access-control-api) и зеркалом olcConnAllowed (drop-sessions).

import (
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/openlibrecommunity/olcrtc/internal/logger"
	"github.com/openlibrecommunity/olcrtc/internal/server"
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

// olcAccDecideConn — решение для ПОДКЛЮЧЕНИЯ при активном энфорсе: banNoHwid,
// списки allow/ban. Пустой allow = блок всех (энфорс включён осознанно).
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

// olcAccDecideBanOnly — режим «Выключено (пускать всех, кроме бан-листа)»:
// пускает всех, КРОМЕ забаненных устройств (+ban_no_hwid, если включён).
// Бан-лист действует ВСЕГДА, даже при выключенном энфорсе (сессия №17).
func olcAccDecideBanOnly(dev string, banNoHwid bool, ban []olcAccDevice) bool {
	if olcAccMatch(ban, dev) {
		return false
	}
	if dev == "" && banNoHwid {
		return false
	}
	return true
}

// throttle warn-логов fail-open (чтобы битый файл не заспамил журнал: хук
// зовётся на каждый handshake, recheck — каждые 2с).
var (
	olcAccWarnMu   sync.Mutex
	olcAccLastWarn time.Time
)

func olcAccWarnf(format string, args ...any) {
	olcAccWarnMu.Lock()
	if time.Since(olcAccLastWarn) < 30*time.Second {
		olcAccWarnMu.Unlock()
		return
	}
	olcAccLastWarn = time.Now()
	olcAccWarnMu.Unlock()
	logger.Warnf(format, args...)
}

// olcAccessConnDecide — ЧИСТОЕ решение «пускать ли устройство dev на этот
// инстанс» при текущем access-control.json. Единая точка истины для handshake
// (AuthHook) и для ban-watcher (recheck живых сессий). false = явный запрет.
// Fail-open (true) при ошибке чтения/парса файла — с warn-логом (кроме ENOENT).
func olcAccessConnDecide(deviceID string) bool {
	dev := strings.TrimSpace(deviceID)
	data, err := os.ReadFile(olcAccessControlPath)
	if err != nil {
		if !os.IsNotExist(err) {
			olcAccWarnf("olc-access: read config failed (fail-open): %v", err)
		}
		return true
	}
	var ac olcAccControl
	if err := json.Unmarshal(data, &ac); err != nil {
		olcAccWarnf("olc-access: parse config failed (fail-open): %v", err)
		return true
	}
	room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
	// ГЛОБАЛЬНЫЙ контроль включён (enabled): применяется глобальный энфорс
	// подключения; выборочный per-client НЕ работает (шестерёнка недоступна).
	// Бан-лист подключения действует ВСЕГДА (и при выключенном энфорсе).
	if ac.Enabled {
		if ac.EnforceConns {
			return olcAccDecideConn(dev, ac.BanNoHwid, ac.ConnDevices, ac.ConnBan)
		}
		return olcAccDecideBanOnly(dev, ac.BanNoHwid, ac.ConnBan)
	}
	// ГЛОБАЛЬНЫЙ контроль ВЫКЛЮЧЕН → работает ВЫБОРОЧНЫЙ per-client (по подписке).
	cid := strings.TrimSpace(os.Getenv("OLCRTC_CLIENT_ID"))
	if cid != "" && ac.Clients != nil {
		if cc, ok := ac.Clients[cid]; ok && cc != nil {
			if cc.ConnEnforce {
				if cc.ConnScope == "selective" {
					inList := false
					for _, r := range cc.ConnInstances {
						if strings.TrimSpace(r) == room && room != "" {
							inList = true
							break
						}
					}
					if !inList {
						return false // selective = вайтлист инстансов: не выбран → запрет
					}
				}
				return olcAccDecideConn(dev, cc.BanNoHwid, cc.ConnAllow, cc.ConnBan)
			}
			return olcAccDecideBanOnly(dev, cc.BanNoHwid, cc.ConnBan)
		}
	}
	return true
}

func olcAccessConnectionAuthHook(deviceID string, _ map[string]any) (string, error) {
	dev := strings.TrimSpace(deviceID)
	if olcAccessConnDecide(dev) {
		// Принятые подключения видны по «peer connected: device=…» —
		// отдельная allowed=true строка не нужна (и ломала счёт журнала).
		return uuid.NewString(), nil
	}
	room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
	logger.Infof("olc-access: conn attempt device=%s allowed=false room=%s", dev, room)
	return "", errors.New("device not allowed to connect")
}

// Регистрация recheck-решения для ban-watcher (internal/server).
func init() {
	server.OlcBanRecheck = olcAccessConnDecide
}
GO
echo "[patch-olcrtc-core-access-hook] wrote $HOOK_GO"

# 2. Ban-watcher в package server (новый файл — доступ к приватным полям Server).
cat > "$WATCHER_GO" <<'GO'
package server

// Olc-cost-l: ban-watcher — непрерывный энфорс контроля доступа на ЖИВЫХ
// сессиях. Handshake-хук (AuthHook) отбивает только НОВЫЕ подключения; уже
// подключённый девайс раньше жил до реконнекта, а менеджер рвал его РЕСТАРТОМ
// всего инстанса (страдали остальные девайсы). Watcher каждые 2с пере-проверяет
// живые сессии решением OlcBanRecheck (то же, что у handshake) и кикает ТОЧЕЧНО:
//   - per-peer сессия → removePeerSession("banned"): клиенту уходит control
//     CLOSE → olcbox мгновенно видит разрыв; остальные пиры не затронуты;
//   - singleton-сессия → reinstallSession: smux пересоздаётся, sessionID
//     сбрасывается → клиент обязан пройти handshake заново → REJECT хуком.
// Ленивый старт при первом открытии сессии; остановка по s.done.
// Заодно добивает «утёкшие» сессии (редкий fail-open на handshake) за ≤2с.

import (
	"sync"
	"time"

	"github.com/openlibrecommunity/olcrtc/internal/logger"
)

// OlcBanRecheck — решение контроля доступа для устройства (единая логика с
// AuthHook). Устанавливается из package session (init в olc_access_hook.go).
// nil = watcher выключен (ядро без панельного контроля доступа).
var OlcBanRecheck func(deviceID string) bool

var (
	olcBanWatchMu sync.Mutex
	olcBanWatched = map[*Server]bool{}
)

// olcEnsureBanWatcher лениво запускает watcher (один на Server).
func (s *Server) olcEnsureBanWatcher() {
	if OlcBanRecheck == nil || s == nil || s.done == nil {
		return
	}
	olcBanWatchMu.Lock()
	defer olcBanWatchMu.Unlock()
	if olcBanWatched[s] {
		return
	}
	olcBanWatched[s] = true
	go s.olcBanWatcher()
}

func (s *Server) olcBanWatcher() {
	defer func() {
		olcBanWatchMu.Lock()
		delete(olcBanWatched, s)
		olcBanWatchMu.Unlock()
	}()
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-t.C:
			s.olcDropBannedPeers()
		}
	}
}

// olcDropBannedPeers рвёт сессии устройств, не проходящих ТЕКУЩУЮ проверку
// доступа. Формат лог-строк: "olc-access: kick dev=…" — НАМЕРЕННО без токена
// "device=" (его считает парсер журнала подключений менеджера; сам кик journal
// видит по "peer disconnected: … reason=banned").
func (s *Server) olcDropBannedPeers() {
	recheck := OlcBanRecheck
	if recheck == nil {
		return
	}
	type peerRef struct{ id, dev string }
	s.sessMu.RLock()
	singleDev := s.deviceID
	singleSID := s.sessionID
	cur := s.session
	if cur == nil {
		cur = s.controlSess
	}
	peers := make([]peerRef, 0, len(s.peerSessions))
	peerDevs := map[string]bool{}
	for id, ps := range s.peerSessions {
		if ps != nil && ps.deviceID != "" {
			peers = append(peers, peerRef{id: id, dev: ps.deviceID})
			peerDevs[ps.deviceID] = true
		}
	}
	s.sessMu.RUnlock()
	for _, p := range peers {
		if !recheck(p.dev) {
			logger.Infof("olc-access: kick dev=%s peer=%s reason=banned", p.dev, p.id)
			s.removePeerSession(p.id, "banned")
		}
	}
	// Singleton: кикаем через reinstall ТОЛЬКО если девайс не покрыт per-peer
	// киком выше (в legacy-путях singleton-поля зеркалят последний peer-handshake
	// — не рвать чужой smux без причины).
	if singleSID != "" && singleDev != "" && !peerDevs[singleDev] && !recheck(singleDev) {
		logger.Infof("olc-access: kick dev=%s session=%s reason=banned (reinstall)", singleDev, singleSID)
		s.reinstallSession(cur)
	}
}
GO
echo "[patch-olcrtc-core-access-hook] wrote $WATCHER_GO"

# 3. Вставить AuthHook в server.Config литерал (перед OnSessionOpen).
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

# 4. Запуск ban-watcher: ленивый старт при первом открытии сессии (trackPeerOpen
#    вызывается ОБОИМИ путями handshake — singleton и per-peer).
python3 - "$SERVER_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
if 'olcEnsureBanWatcher()' in t:
    print("[patch-olcrtc-core-access-hook] ban-watcher already wired")
    sys.exit(0)
anchor = 'func (s *Server) trackPeerOpen(sessionID, deviceID string) {\n\ts.peersMu.Lock()'
repl = 'func (s *Server) trackPeerOpen(sessionID, deviceID string) {\n\ts.olcEnsureBanWatcher()\n\ts.peersMu.Lock()'
if anchor in t:
    t = t.replace(anchor, repl, 1)
    f.write_text(t)
    print("[patch-olcrtc-core-access-hook] wired olcEnsureBanWatcher into trackPeerOpen")
else:
    print("[patch-olcrtc-core-access-hook] WARN: trackPeerOpen anchor not found — watcher file present but not started")
PY
