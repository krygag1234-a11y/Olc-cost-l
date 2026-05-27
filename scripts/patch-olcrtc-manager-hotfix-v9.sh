#!/usr/bin/env bash
# Hotfix v9: register panelBackendV4 API routes when handlers exist but mux entries are missing.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if 'handler.Handle("/api/components/"' in t:
    print("[patch-manager-hotfix-v9] routes already registered")
    sys.exit(0)

if "func componentsActionHandler" not in t:
    print("[patch-manager-hotfix-v9] skip: no componentsActionHandler", file=sys.stderr)
    sys.exit(0)

routes = """\thandler.Handle("/api/updates/check", adminAuth(http.HandlerFunc(updatesCheckHandler)))
\thandler.Handle("/api/updates/status", adminAuth(http.HandlerFunc(updatesStatusHandler)))
\thandler.Handle("/api/updates/run", adminAuth(http.HandlerFunc(updatesRunHandler)))
\thandler.Handle("/api/jobs/", adminAuth(panelJobsHandler()))
\thandler.Handle("/api/notifications/scan", adminAuth(http.HandlerFunc(notificationsScanHandler)))
\thandler.Handle("/api/notifications/", adminAuth(http.HandlerFunc(notificationsPatchHandler)))
\thandler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler)))
\thandler.Handle("/api/components/", adminAuth(http.HandlerFunc(componentsActionHandler)))
"""

if "func componentsJobsHandler" in t and 'handler.Handle("/api/components/jobs"' not in t:
    routes += '\thandler.Handle("/api/components/jobs", adminAuth(http.HandlerFunc(componentsJobsHandler)))\n'

anchors = [
    '\thandler.Handle("/api/capabilities", adminAuth(http.HandlerFunc(capabilitiesHandler())))',
    '\thandler.Handle("/api/features", adminAuth(http.HandlerFunc(featuresListHandler())))',
]
inserted = False
for anchor in anchors:
    if anchor in t:
        t = t.replace(anchor, routes + anchor, 1)
        inserted = True
        break

if not inserted:
    anchor = '\thandler.Handle("/api/settings/", adminAuth(http.HandlerFunc(componentSettingsHandler())))'
    if anchor in t:
        t = t.replace(anchor, anchor + "\n" + routes, 1)
        inserted = True

if not inserted:
    print("[patch-manager-hotfix-v9] failed: no anchor for routes", file=sys.stderr)
    sys.exit(1)

if "olc-manager-hotfix-v9" not in t:
    if "/* olc-manager-hotfix-v8 */" in t:
        t = t.replace("/* olc-manager-hotfix-v8 */", "/* olc-manager-hotfix-v8 */\n/* olc-manager-hotfix-v9 */", 1)
    else:
        t = "/* olc-manager-hotfix-v9 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v9] ok")
PY
