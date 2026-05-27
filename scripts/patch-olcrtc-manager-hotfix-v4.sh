#!/usr/bin/env bash
# Hotfix v4: ensure /api/project/status route is registered.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
if '/api/project/status' not in t:
    pat = r'(\thandler\.Handle\("/api/settings",\s*adminAuth\(http\.HandlerFunc\(settingsHandler\([^\n]+\)\)\)\)\n)'
    repl = r'\1\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))\n'
    t, n = re.subn(pat, repl, t, count=1)
    if n == 0:
        # fallback near updates routes
        alt = '\thandler.Handle("/api/updates/check", adminAuth(http.HandlerFunc(updatesCheckHandler)))\n'
        if alt in t:
            t = t.replace(alt, '\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))\n' + alt, 1)

if "olc-manager-hotfix-v4" not in t:
    if "/* olc-manager-hotfix-v3 */" in t:
        t = t.replace("/* olc-manager-hotfix-v3 */", "/* olc-manager-hotfix-v3 */\n/* olc-manager-hotfix-v4 */", 1)
    else:
        t = "/* olc-manager-hotfix-v4 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v4] ok")
PY
