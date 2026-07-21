#!/usr/bin/env bash
# Olc-cost-l backend: разрыв активных сессий устройства при отзыве доступа.
# С сессии №18 РЕАЛЬНЫЙ кик делает ЯДРО (ban-watcher в olcrtc-core, патч
# patch-olcrtc-core-access-hook.sh): каждые 2с пере-проверяет живые сессии и
# рвёт ТОЛЬКО сессию нарушителя (removePeerSession/reinstall) — остальные
# девайсы инстанса не страдают. Менеджер после каждого сохранения
# access-control лишь ЛОГИРУЕТ, у кого доступ отозван (для journalctl-разбора).
# Раньше менеджер РЕСТАРТОВАЛ инстанс целиком — рвал туннели ВСЕХ девайсов
# инстанса (жалоба юзера) и не помогал против транспорт-реконнектов.
# Idempotent. Target: manager main.go.
# Run after access-control-api + access-connections-api (нужны типы + panelSupervisor).
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-access-drop-sessions] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# 1. Хелперы olcConnAllowed + olcDropForbiddenSessions (перед func olcAccessSave).
if 'func olcDropForbiddenSessions(' not in t:
    anchor = 'func olcAccessSave(ac olcAccessControl) error {'
    helper = r'''// olcConnMatch — есть ли dev во включённых записях списка.
func olcConnMatch(list []olcAllowedDevice, dev string) bool {
	for _, d := range list {
		if d.Enabled && strings.TrimSpace(d.HWID) != "" && strings.EqualFold(strings.TrimSpace(d.HWID), dev) {
			return true
		}
	}
	return false
}

func olcConnCount(lists ...[]olcAllowedDevice) int {
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

// olcConnAllowed — зеркало AuthHook olcrtc-core: разрешено ли устройству dev
// подключение к инстансу (clientID/roomID) при ТЕКУЩЕМ access-control. Учитывает
// глобальный enforce_connections и выборочный per-client conn_enforce.
// БАН-ЛИСТ подключения действует ВСЕГДА (даже при выключенном энфорсе —
// «Выключено (пускать всех, кроме бан-листа)», сессия №17) → бан рвёт сессию сразу.
func olcConnAllowed(ac olcAccessControl, clientID, roomID, hwid string) bool {
	dev := strings.TrimSpace(hwid)
	decide := func(banNoHwid bool, allow, ban []olcAllowedDevice) bool {
		if olcConnMatch(ban, dev) {
			return false
		}
		if dev == "" {
			return !banNoHwid
		}
		if olcConnMatch(allow, dev) {
			return true
		}
		return false // не в списке (в т.ч. пустой) — блок
	}
	decideBanOnly := func(banNoHwid bool, ban []olcAllowedDevice) bool {
		if olcConnMatch(ban, dev) {
			return false
		}
		if dev == "" && banNoHwid {
			return false
		}
		return true
	}
	// Глобальный вкл → глобальный энфорс; выборочный per-client НЕ действует.
	if ac.Enabled {
		if ac.EnforceConns {
			if ac.ConnScope == "selective" {
				inList := false
				for _, r := range ac.ConnInstances {
					if strings.TrimSpace(r) == strings.TrimSpace(roomID) && roomID != "" {
						inList = true
						break
					}
				}
				if !inList {
					return false // глоб. selective = вайтлист инстансов: не выбран → запрет
				}
			}
			return decide(ac.BanNoHwid, ac.ConnDevices, ac.ConnBan)
		}
		return decideBanOnly(ac.BanNoHwid, ac.ConnBan)
	}
	// Глобальный ВЫКЛ → работает выборочный per-client.
	if ac.Clients != nil {
		if cc, ok := ac.Clients[clientID]; ok && cc != nil {
			if cc.ConnEnforce {
				enforced := true
				if cc.ConnScope == "selective" {
					enforced = false
					inList := false
					for _, r := range cc.ConnInstances {
						if strings.TrimSpace(r) == strings.TrimSpace(roomID) && roomID != "" {
							enforced = true
							inList = true
							break
						}
					}
					if !inList {
						return false // инстанс НЕ выбран → подключение запрещено
					}
				}
				if enforced {
					return decide(cc.BanNoHwid, cc.ConnAllow, cc.ConnBan)
				}
			} else {
				return decideBanOnly(cc.BanNoHwid, cc.ConnBan)
			}
		}
	}
	return true
}

// olcDropForbiddenSessions — с сессии №18 НЕ рестартует инстансы: точечный кик
// нарушителя делает ЯДРО (ban-watcher, ≤2с, только его сессия). Здесь лишь
// логируем в journalctl, каким ЖИВЫМ девайсам доступ отозван этим сохранением
// (по peer-summary «Current peers count» — живые пиры, источник истины).
func olcDropForbiddenSessions(ac olcAccessControl) {
	if panelSupervisor == nil {
		return
	}
	go func() {
		panelSupervisor.mu.RLock()
		procs := make([]*process, 0, len(panelSupervisor.processes))
		for _, p := range panelSupervisor.processes {
			procs = append(procs, p)
		}
		panelSupervisor.mu.RUnlock()
		for _, p := range procs {
			if p == nil || p.logs == nil {
				continue
			}
			cid := p.location.ClientID
			room := p.location.Endpoint.RoomID
			seen := map[string]bool{}
			if pc, devs, _, ok := p.logs.PeerSummary(); ok && pc > 0 {
				for _, dev := range devs {
					dev = strings.TrimSpace(dev)
					if dev == "" || seen[dev] {
						continue
					}
					seen[dev] = true
					if !olcConnAllowed(ac, cid, room, dev) {
						log.Printf("olc-access: revoked live dev=%s inst=%s/%s — kick ядром (ban-watcher, ~2с)", dev, cid, room)
					}
				}
			}
		}
	}()
}

var olcDeviceLineRe = regexp.MustCompile(`device=([^\s)]+)`)

'''
    t = t.replace(anchor, helper + anchor, 1)
    changed = True
    print("[patch-access-drop-sessions] added olcConnAllowed + olcDropForbiddenSessions")
else:
    print("[patch-access-drop-sessions] helpers already present")

# 2. Вызвать drop после успешного сохранения (в конце olcAccessSave, перед return Rename).
save_old = '''	tmp := olcAccessControlPath + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, olcAccessControlPath)
}'''
save_new = '''	tmp := olcAccessControlPath + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\\n'), 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, olcAccessControlPath); err != nil {
		return err
	}
	olcDropForbiddenSessions(ac) // лог отозванных живых девайсов (кик — ядром)
	return nil
}'''
if 'olcDropForbiddenSessions(ac) //' in t:
    print("[patch-access-drop-sessions] save-hook already present")
elif save_old in t:
    t = t.replace(save_old, save_new, 1)
    changed = True
    print("[patch-access-drop-sessions] hooked olcDropForbiddenSessions into olcAccessSave")
else:
    print("[patch-access-drop-sessions] WARN: olcAccessSave tail anchor not found — drop not hooked")

if changed:
    f.write_text(t)
    print("[patch-access-drop-sessions] OK: main.go updated")
else:
    print("[patch-access-drop-sessions] no changes (idempotent)")
PY
