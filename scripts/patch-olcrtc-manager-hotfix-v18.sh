#!/usr/bin/env bash
# Hotfix v18: component jobs treat failed+done-marker as done.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v18' "$MAIN_GO" && { echo "[patch-manager-hotfix-v18] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "func fileContainsDoneMarker(" not in t:
    helper = r'''
func fileContainsDoneMarker(path string) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return strings.Contains(string(b), "=== done ===")
}

'''
    t = t.replace("func componentJobStale(st map[string]any, mod time.Time) bool {", helper + "func componentJobStale(st map[string]any, mod time.Time) bool {", 1)

needle = r'''\t\tif status, _ := st["status"].(string); (status == "done" || status == "failed") && st["finished_at"] == nil {
\t\t\tst["finished_at"] = info.ModTime().Format(time.RFC3339)
\t\t}'''

patch = r'''\t\tif status, _ := st["status"].(string); status == "failed" {
\t\t\tlogPath, _ := st["log_path"].(string)
\t\t\tif logPath != "" && fileContainsDoneMarker(logPath) {
\t\t\t\tst["status"] = "done"
\t\t\t\tst["exit_code"] = 0
\t\t\t\tst["error"] = ""
\t\t\t\tstatus = "done"
\t\t\t}
\t\t}
\t\tif status, _ := st["status"].(string); (status == "done" || status == "failed") && st["finished_at"] == nil {
\t\t\tst["finished_at"] = info.ModTime().Format(time.RFC3339)
\t\t}'''

if needle in t:
    t = t.replace(needle, patch, 1)
else:
    print("[patch-manager-hotfix-v18] target block not found", file=sys.stderr)
    sys.exit(1)

if "/* olc-manager-hotfix-v18 */" not in t:
    if "/* olc-manager-hotfix-v17 */" in t:
        t = t.replace("/* olc-manager-hotfix-v17 */", "/* olc-manager-hotfix-v17 */\n/* olc-manager-hotfix-v18 */", 1)
    else:
        t = "/* olc-manager-hotfix-v18 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v18] ok")
PY
