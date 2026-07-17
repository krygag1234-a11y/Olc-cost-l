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
fn_block = r'''// accessConnectionsHandler: парсит journal olcrtc-manager и отдаёт устройства,
// подключавшиеся к инстансам (device=install-… в строках peer session). Read-only;
// тот же идентификатор, что и allowlist подписки. См. docs/ACCESS-CONTROL.md.
func accessConnectionsHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "journalctl", "-u", "olcrtc-manager", "-n", "3000", "--no-pager", "-o", "short-iso")
	out, _ := cmd.CombinedOutput()
	re := regexp.MustCompile(`device=(install-[0-9a-fA-F]+)`)
	type accConn struct {
		Device string `json:"device"`
		Count  int    `json:"count"`
		Last   string `json:"last"`
	}
	order := []string{}
	byDev := map[string]*accConn{}
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
		c, ok := byDev[dev]
		if !ok {
			c = &accConn{Device: dev}
			byDev[dev] = c
			order = append(order, dev)
		}
		c.Count++
		c.Last = ts
	}
	list := []accConn{}
	for _, d := range order {
		list = append(list, *byDev[d])
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
