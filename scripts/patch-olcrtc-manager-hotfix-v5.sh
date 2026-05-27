#!/usr/bin/env bash
# Hotfix v5: ensure notification settings route exists.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if '/api/notification-settings' not in t:
    # Preferred insertion: near notifications routes.
    anchor = '\thandler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler)))\n'
    route = '\thandler.Handle("/api/notification-settings", adminAuth(http.HandlerFunc(notificationSettingsHandler)))\n'
    if anchor in t:
        t = t.replace(anchor, route + anchor, 1)
    else:
        # Fallback insertion near /api/settings route.
        pat = r'(\thandler\.Handle\("/api/settings",\s*adminAuth\(http\.HandlerFunc\(settingsHandler\([^\n]+\)\)\)\)\n)'
        t, n = re.subn(pat, r'\1' + route, t, count=1)
        if n == 0:
            alt = '\thandler.Handle("/api/reload", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {\n'
            if alt in t:
                t = t.replace(alt, route + alt, 1)

if "olc-manager-hotfix-v5" not in t:
    marker_from = "/* olc-manager-hotfix-v4 */"
    marker_to = "/* olc-manager-hotfix-v4 */\n/* olc-manager-hotfix-v5 */"
    if marker_from in t:
        t = t.replace(marker_from, marker_to, 1)
    else:
        t = "/* olc-manager-hotfix-v5 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v5] ok")
PY
