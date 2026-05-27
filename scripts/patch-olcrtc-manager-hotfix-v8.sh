#!/usr/bin/env bash
# Hotfix v8: fix unknown component/feature for olcrtc and warp API endpoints.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# component settings handler should allow olcrtc+warp.
t = t.replace(
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true}',
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true, "warp": true}',
)

# feature logs should accept olcrtc key (used by panel logs button).
if 'for _, n := range featureNames {' in t and 'name == "olcrtc"' not in t:
    t = t.replace(
        '\t\tif !allowed {\n\t\t\thttp.Error(w, "unknown feature", http.StatusBadRequest)\n\t\t\treturn\n\t\t}\n',
        '\t\tif !allowed && name == "olcrtc" {\n\t\t\tallowed = true\n\t\t}\n\t\tif !allowed {\n\t\t\thttp.Error(w, "unknown feature", http.StatusBadRequest)\n\t\t\treturn\n\t\t}\n',
        1,
    )

# featureLogPaths: add olcrtc case if absent.
if 'case "olcrtc":' not in t and 'func featureLogPaths(name string)' in t:
    t = t.replace(
        '\tcase "webtunnel":\n\t\treturn []string{"/var/log/olcrtc-healthcheck.log"}\n',
        '\tcase "webtunnel":\n\t\treturn []string{"/var/log/olcrtc-healthcheck.log"}\n\tcase "olcrtc":\n\t\treturn []string{"/var/log/olcrtc-healthcheck.log", "/var/log/syslog"}\n',
        1,
    )

if "olc-manager-hotfix-v8" not in t:
    t = "/* olc-manager-hotfix-v8 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v8] ok")
PY
