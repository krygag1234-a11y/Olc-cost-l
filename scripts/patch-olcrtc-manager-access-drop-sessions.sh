#!/usr/bin/env bash
# Olc-cost-l backend: МГНОВЕННЫЙ разрыв активных сессий устройства при отзыве
# доступа. Баг юзера: выключил разрешённое устройство галочкой — а активный
# туннель не рвётся сразу, блок срабатывает лишь при повторном подключении.
# Решение: после КАЖДОГО сохранения access-control (disable/ban/remove/смена
# режима/тоггл энфорса) пере-оценить подключённые устройства и перезапустить
# инстансы, где есть подключённое устройство, которое БОЛЬШЕ НЕ разрешено при
# активном энфорсе подключения. Перезапуск инстанса рвёт сессию нарушителя;
# разрешённые устройства сразу переподключаются (проходят AuthHook).
# Без активного энфорса подключения ничего не рвём (иначе устройство всё равно
# переподключится — как и раньше). Idempotent. Target: manager main.go.
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
// глобальный enforce_connections и выборочный per-client conn_enforce. Если энфорс
// подключения НЕ активен для этого инстанса — true (не трогаем).
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
	// Глобальный вкл → глобальный энфорс; выборочный per-client НЕ действует.
	if ac.Enabled {
		if ac.EnforceConns {
			return decide(ac.BanNoHwid, ac.ConnDevices, ac.ConnBan)
		}
		return true
	}
	// Глобальный ВЫКЛ → работает выборочный per-client.
	if ac.Clients != nil {
		if cc, ok := ac.Clients[clientID]; ok && cc != nil && cc.ConnEnforce {
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
		}
	}
	return true
}

// olcDropForbiddenSessions — перезапускает инстансы, где подключено устройство,
// которое больше не разрешено (по текущему ac). Вызывается после сохранения
// access-control. Идёт по per-instance лог-буферам (device=install-…).
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
		re := olcDeviceLineRe
		for _, p := range procs {
			if p == nil || p.logs == nil {
				continue
			}
			cid := p.location.ClientID
			room := p.location.Endpoint.RoomID
			tr := p.location.Transport.Type
			forbidden := false
			seen := map[string]bool{}
			for _, ln := range p.logs.Snapshot() {
				mm := re.FindStringSubmatch(ln.Line)
				if mm == nil {
					continue
				}
				dev := mm[1]
				if seen[dev] {
					continue
				}
				seen[dev] = true
				if !olcConnAllowed(ac, cid, room, dev) {
					forbidden = true
					break
				}
			}
			if forbidden {
				ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
				if err := panelSupervisor.Restart(ctx, cid, room, tr); err != nil {
					log.Printf("olc-access: drop-restart %s/%s: %v", cid, room, err)
				} else {
					log.Printf("olc-access: инстанс %s/%s перезапущен — отозван доступ устройства", cid, room)
				}
				cancel()
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
	olcDropForbiddenSessions(ac) // мгновенно рвём сессии отозванных устройств
	return nil
}'''
if 'olcDropForbiddenSessions(ac) // мгновенно' in t:
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
