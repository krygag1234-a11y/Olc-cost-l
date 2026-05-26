#!/usr/bin/env bash
# Fast DELETE location: async host sync + async reload (panel must not hang).
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'asyncReloadAfterLocationDelete' "$MAIN_GO" && { echo "[patch-async-delete] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old_sync = """func syncPanelCarrierHost(action, carrier, roomID string) {
\tscript := panelHostSyncScript()
\tif script == \"\" {
\t\treturn
\t}
\tcarrier = strings.TrimSpace(carrier)
\troomID = strings.TrimSpace(roomID)
\tif carrier == \"\" || roomID == \"\" {
\t\treturn
\t}
\tcmd := exec.Command(\"bash\", script, action, carrier, roomID)
\tcmd.Env = append(os.Environ(), \"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\")
\tif out, err := cmd.CombinedOutput(); err != nil {
\t\tlog.Printf(\"panel host sync %s %s: %v (%s)\", action, roomID, err, strings.TrimSpace(string(out)))
\t}
}"""

new_sync = """func syncPanelCarrierHost(action, carrier, roomID string) {
\tscript := panelHostSyncScript()
\tif script == \"\" {
\t\treturn
\t}
\tcarrier = strings.TrimSpace(carrier)
\troomID = strings.TrimSpace(roomID)
\tif carrier == \"\" || roomID == \"\" {
\t\treturn
\t}
\tgo func() {
\t\tcmd := exec.Command(\"bash\", script, action, carrier, roomID)
\t\tenv := append(os.Environ(), \"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\")
\t\tif action == \"remove\" {
\t\t\tenv = append(env, \"OLC_SKIP_ZAPRET_SYNC=1\")
\t\t}
\t\tcmd.Env = env
\t\tif out, err := cmd.CombinedOutput(); err != nil {
\t\t\tlog.Printf(\"panel host sync %s %s: %v (%s)\", action, roomID, err, strings.TrimSpace(string(out)))
\t\t}
\t}()
}"""

if old_sync in t:
    t = t.replace(old_sync, new_sync, 1)
else:
    print("[patch-async-delete] syncPanelCarrierHost block not found — skip")

old_del = """\t\tif err := deleteLocation(configPath, parts[0], parts[1]); err != nil {
\t\t\t\thttp.Error(w, err.Error(), http.StatusBadRequest)
\t\t\t\treturn
\t\t\t}
\t\t\tif err := reload(); err != nil {
\t\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\t\treturn
\t\t\t}
\t\t\tw.WriteHeader(http.StatusNoContent)
\t\t\treturn"""

new_del = """\t\tif err := deleteLocation(configPath, parts[0], parts[1]); err != nil {
\t\t\t\thttp.Error(w, err.Error(), http.StatusBadRequest)
\t\t\t\treturn
\t\t\t}
\t\t\tgo asyncReloadAfterLocationDelete(reload)
\t\t\tw.WriteHeader(http.StatusNoContent)
\t\t\treturn"""

if old_del in t:
    t = t.replace(old_del, new_del, 1)
else:
    raise SystemExit("[patch-async-delete] delete handler block not found")

helper = """
func asyncReloadAfterLocationDelete(reloadFn func() error) {
\tgo func() {
\t\tif err := reloadFn(); err != nil {
\t\t\tlog.Printf(\"reload after location delete: %v\", err)
\t\t}
\t}()
}
"""

if "func asyncReloadAfterLocationDelete" not in t:
    t = t.replace("func syncPanelCarrierHost", helper + "\nfunc syncPanelCarrierHost", 1)

p.write_text(t)
print("[patch-async-delete] ok")
PY
