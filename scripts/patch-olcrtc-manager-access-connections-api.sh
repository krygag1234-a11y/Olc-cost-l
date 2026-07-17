#!/usr/bin/env bash
# Olc-cost-l backend: монитор подключений к инстансам по device (read-only).
#
# olcrtc-core логирует при подключении: "peer session <sid> opened (peer=<p>
# device=install-<hex>)" / "session <sid> opened (device=install-<hex>)". Этот
# device == тот же hwid, что olcbox шлёт при запросе подписки (persistent
# per-install id). Значит ОДИН allowlist покрывает и подписку, и подключение.
#
# Этот эндпоинт (read-only) парсит journal olcrtc-manager и отдаёт последние
# устройства, подключавшиеся к инстансам, чтобы их было видно и можно было
# добавить в allowlist. Enforcement на уровне подключения (AuthHook olcrtc-core)
# — отдельный шаг (см. docs/ACCESS-CONTROL.md).
#   GET /api/access/connections → {connections:[{device,count,last}]}
# Idempotent. Target: manager main.go. Run after access-control-api.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-access-connections-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Роут (после /api/access/remove) ---
route_anchor = '\thandler.Handle("/api/access/remove", adminAuth(http.HandlerFunc(accessRemoveHandler)))'
route_add = route_anchor + '''
	handler.Handle("/api/access/connections", adminAuth(http.HandlerFunc(accessConnectionsHandler)))'''
if '/api/access/connections' in t:
    print("[patch-access-connections-api] route already present")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1); changed = True
    print("[patch-access-connections-api] registered /api/access/connections")
else:
    print("[patch-access-connections-api] WARN: access/remove route anchor not found — skip route")

# --- 2. Обработчик (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// accessConnectionsHandler: отдаёт устройства (device=install-…), подключавшиеся к
// инстансам, С ПРИВЯЗКОЙ к клиенту/инстансу. Источник — per-instance лог-буферы
// (panelSupervisor.processes): менеджер знает, какому клиенту/локации принадлежит
// каждый процесс olcrtc, поэтому device можно сопоставить с подпиской и инстансом.
// Фолбэк — journal olcrtc-manager (без привязки), если буферы пусты. Read-only;
// device == тот же hwid, что allowlist подписки. См. docs/ACCESS-CONTROL.md.
func accessConnectionsHandler(w http.ResponseWriter, r *http.Request) {
	re := regexp.MustCompile(`device=(install-[0-9a-fA-F]+)`)
	type accConn struct {
		Device       string `json:"device"`
		ClientID     string `json:"client_id"`
		LocationName string `json:"location_name"`
		RoomID       string `json:"room_id"`
		Transport    string `json:"transport"`
		Count        int    `json:"count"`
		Last         string `json:"last"`
	}
	order := []string{}
	byKey := map[string]*accConn{}
	if panelSupervisor != nil {
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
			lname := p.location.Name
			room := p.location.Endpoint.RoomID
			tr := p.location.Transport.Type
			for _, ln := range p.logs.Snapshot() {
				mm := re.FindStringSubmatch(ln.Line)
				if mm == nil {
					continue
				}
				dev := mm[1]
				key := dev + "|" + cid + "|" + room + "|" + tr
				c, ok := byKey[key]
				if !ok {
					c = &accConn{Device: dev, ClientID: cid, LocationName: lname, RoomID: room, Transport: tr}
					byKey[key] = c
					order = append(order, key)
				}
				c.Count++
				if ln.Time > c.Last {
					c.Last = ln.Time
				}
			}
		}
	}
	if len(order) == 0 {
		// Фолбэк: journal olcrtc-manager (без привязки к инстансу).
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()
		out, _ := exec.CommandContext(ctx, "journalctl", "-u", "olcrtc-manager", "-n", "3000", "--no-pager", "-o", "short-iso").CombinedOutput()
		for _, line := range strings.Split(string(out), "\n") {
			mm := re.FindStringSubmatch(line)
			if mm == nil {
				continue
			}
			dev := mm[1]
			ts := ""
			if fields := strings.Fields(line); len(fields) > 0 {
				ts = fields[0]
			}
			c, ok := byKey[dev]
			if !ok {
				c = &accConn{Device: dev}
				byKey[dev] = c
				order = append(order, dev)
			}
			c.Count++
			c.Last = ts
		}
	}
	list := []accConn{}
	for _, k := range order {
		list = append(list, *byKey[k])
	}
	writeJSON(w, map[string]any{"connections": list})
}

'''
if 'func accessConnectionsHandler(' in t:
    print("[patch-access-connections-api] handler already present")
elif fn_anchor in t:
    t = t.replace(fn_anchor, fn_block + fn_anchor, 1); changed = True
    print("[patch-access-connections-api] added accessConnectionsHandler")
else:
    print("[patch-access-connections-api] WARN: writeJSON anchor not found — skip handler")

if changed:
    f.write_text(t)
    print("[patch-access-connections-api] OK: main.go updated")
else:
    print("[patch-access-connections-api] no changes (idempotent)")
PY
