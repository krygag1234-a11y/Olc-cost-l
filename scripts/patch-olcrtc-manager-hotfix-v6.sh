#!/usr/bin/env bash
# Hotfix v6: stable WARP detection + warp in feature whitelist.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

t = t.replace(
    'var featureNames = []string{"zapret", "tor", "split", "webtunnel"}',
    'var featureNames = []string{"zapret", "tor", "split", "webtunnel", "warp"}',
)

start = t.find("func componentInstalled(name string) bool {")
end = t.find("func loadFeatureFlagsMap()", start)
if start != -1 and end != -1:
    block = t[start:end]
    if 'case "warp":' not in block:
        block = block.replace(
            '\tcase "bridges", "webtunnel":\n',
            '\tcase "warp":\n'
            '\t\tif _, err := os.Stat("/usr/bin/warp-cli"); err == nil {\n'
            '\t\t\treturn true\n'
            '\t\t}\n'
            '\t\tif _, err := os.Stat("/usr/local/bin/warp-cli"); err == nil {\n'
            '\t\t\treturn true\n'
            '\t\t}\n'
            '\t\tif _, err := os.Stat("/var/lib/cloudflare-warp"); err == nil {\n'
            '\t\t\treturn true\n'
            '\t\t}\n'
            '\t\treturn false\n'
            '\tcase "bridges", "webtunnel":\n',
            1,
        )
        t = t[:start] + block + t[end:]

if "olc-manager-hotfix-v6" not in t:
    marker = "/* olc-manager-hotfix-v5 */"
    if marker in t:
        t = t.replace(marker, marker + "\n/* olc-manager-hotfix-v6 */", 1)
    else:
        t = "/* olc-manager-hotfix-v6 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v6] ok")
PY
