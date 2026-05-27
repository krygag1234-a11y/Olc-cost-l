#!/usr/bin/env bash
# Hotfix v10: warp in /api/capabilities + component-removed markers in componentInstalled.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "func componentRemovedMarker(name string) bool" not in t:
    helper = '''
func componentRemovedMarker(name string) bool {
	_, err := os.Stat(filepath.Join("/var/lib/olcrtc/component-removed", name))
	return err == nil
}

'''
    anchor = "func componentInstalled(name string) bool {"
    if anchor in t:
        t = t.replace(anchor, helper + anchor, 1)

start = t.find("func componentInstalled(name string) bool {")
end = t.find("\nfunc ", start + 1)
if start != -1 and end != -1:
    block = t[start:end]
    if "componentRemovedMarker(name)" not in block:
        block = block.replace(
            "func componentInstalled(name string) bool {\n\tswitch name {",
            "func componentInstalled(name string) bool {\n\tif componentRemovedMarker(name) {\n\t\treturn false\n\t}\n\tswitch name {",
            1,
        )
        t = t[:start] + block + t[end:]

# capabilitiesHandler: add warp component entry
cap = t.find("func capabilitiesHandler()")
if cap != -1:
    slice_ = t[cap : cap + 2500]
    if '"warp":' not in slice_.split("writeJSON(w, map[string]any{")[0]:
        old = '''\t\t\t"bridges": {
\t\t\t\tInstalled: componentInstalled("bridges"), Enabled: flags["webtunnel"],
\t\t\t\tConfigurable: componentInstalled("tor"), Label: "Мосты",
\t\t\t},
\t\t}
\t\twriteJSON(w, map[string]any{'''
        new = '''\t\t\t"bridges": {
\t\t\t\tInstalled: componentInstalled("bridges"), Enabled: flags["webtunnel"],
\t\t\t\tConfigurable: componentInstalled("tor"), Label: "Мосты",
\t\t\t},
\t\t\t"warp": {
\t\t\t\tInstalled: componentInstalled("warp"), Enabled: flags["warp"],
\t\t\t\tConfigurable: componentInstalled("warp"), Label: "WARP",
\t\t\t},
\t\t}
\t\twriteJSON(w, map[string]any{'''
        if old in t:
            t = t.replace(old, new, 1)

# loadFeatureFlagsMap default must include warp
if 'flags := map[string]bool{"zapret": true, "tor": true, "split": true, "webtunnel": true}' in t:
    t = t.replace(
        'flags := map[string]bool{"zapret": true, "tor": true, "split": true, "webtunnel": true}',
        'flags := map[string]bool{"zapret": true, "tor": true, "split": true, "webtunnel": true, "warp": false}',
        1,
    )

if "olc-manager-hotfix-v10" not in t:
    if "/* olc-manager-hotfix-v9 */" in t:
        t = t.replace("/* olc-manager-hotfix-v9 */", "/* olc-manager-hotfix-v9 */\n/* olc-manager-hotfix-v10 */", 1)
    else:
        t = "/* olc-manager-hotfix-v10 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v10] ok")
PY
