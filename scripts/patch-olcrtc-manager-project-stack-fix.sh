#!/usr/bin/env bash
# Project status: bridges flag from webtunnel toggle; display flags without raw webtunnel key.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'displayFeatureFlags' "$MAIN_GO" && { echo "[patch-project-stack-fix] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helper = r'''
func displayFeatureFlags() map[string]bool {
	raw := readFeatureFlags()
	out := map[string]bool{
		"zapret":  raw["zapret"],
		"tor":     raw["tor"],
		"split":   raw["split"],
		"bridges": raw["webtunnel"],
		"warp":    raw["warp"],
		"olcrtc":  raw["olcrtc"],
	}
	return out
}

'''

if "func displayFeatureFlags" not in t:
    anchor = "func componentStackStatus()"
    if anchor not in t:
        anchor = "func projectStatusHandler"
    t = t.replace(anchor, helper + anchor, 1)

t = t.replace(
    'enabled := flags[id]',
    'enabled := flags[id]\n\t\tif id == "bridges" {\n\t\t\tenabled = flags["webtunnel"]\n\t\t}',
    1,
)

for old in ('"flags": readFeatureFlags(),', '"flags": readFeatureFlags(),'):
    if old in t:
        t = t.replace(old, '"flags": displayFeatureFlags(),', 1)
        break

p.write_text(t)
print("[patch-project-stack-fix] ok")
PY
