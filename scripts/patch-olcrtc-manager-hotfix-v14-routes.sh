#!/usr/bin/env bash
# Hotfix v14: register core panel API routes (features, capabilities, settings, components).
# Fixes apply when v9 anchor missing (features route not yet in mux).
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if 'handler.Handle("/api/features"' in t and 'handler.Handle("/api/capabilities"' in t:
    print("[patch-manager-hotfix-v14] routes already registered")
    sys.exit(0)

routes = []
need = [
    ('handler.Handle("/api/features"', '\thandler.Handle("/api/features", adminAuth(http.HandlerFunc(featuresListHandler())))\n'),
    ('handler.Handle("/api/features/"', '\thandler.Handle("/api/features/", adminAuth(http.HandlerFunc(featuresToggleHandler())))\n'),
    ('handler.Handle("/api/capabilities"', '\thandler.Handle("/api/capabilities", adminAuth(http.HandlerFunc(capabilitiesHandler())))\n'),
    ('handler.Handle("/api/settings/"', '\thandler.Handle("/api/settings/", adminAuth(http.HandlerFunc(componentSettingsHandler())))\n'),
    ('handler.Handle("/api/updates/check"', '\thandler.Handle("/api/updates/check", adminAuth(http.HandlerFunc(updatesCheckHandler)))\n'),
    ('handler.Handle("/api/components/"', '\thandler.Handle("/api/components/", adminAuth(http.HandlerFunc(componentsActionHandler)))\n'),
]
for token, line in need:
    if token not in t:
        routes.append(line)

if "func componentsJobsHandler" in t and 'handler.Handle("/api/components/jobs"' not in t:
    routes.append('\thandler.Handle("/api/components/jobs", adminAuth(http.HandlerFunc(componentsJobsHandler)))\n')

for extra in [
    '\thandler.Handle("/api/updates/status", adminAuth(http.HandlerFunc(updatesStatusHandler)))\n',
    '\thandler.Handle("/api/updates/run", adminAuth(http.HandlerFunc(updatesRunHandler)))\n',
    '\thandler.Handle("/api/jobs/", adminAuth(panelJobsHandler()))\n',
    '\thandler.Handle("/api/notifications/scan", adminAuth(http.HandlerFunc(notificationsScanHandler)))\n',
    '\thandler.Handle("/api/notifications/", adminAuth(http.HandlerFunc(notificationsPatchHandler)))\n',
    '\thandler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler)))\n',
]:
    token = extra.split("(")[0].strip()
    if token.replace("handler.Handle", 'handler.Handle("')[:30] in t:
        continue
    key = extra.split('"')[1]
    if f'handler.Handle("{key}"' not in t:
        routes.append(extra)

if not routes:
    print("[patch-manager-hotfix-v14] nothing to add")
    sys.exit(0)

block = "".join(routes)
anchors = [
    '\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))',
    '\thandler.Handle("/api/notification-settings", adminAuth(http.HandlerFunc(notificationSettingsHandler)))',
    '\thandler.Handle("/api/settings", adminAuth(http.HandlerFunc(settingsHandler(configPath, supervisor, port != 0))))',
]
inserted = False
for anchor in anchors:
    if anchor in t:
        t = t.replace(anchor, block + anchor, 1)
        inserted = True
        break

if not inserted:
    print("[patch-manager-hotfix-v14] failed: no anchor", file=sys.stderr)
    sys.exit(1)

if "olc-manager-hotfix-v14" not in t:
    t = "/* olc-manager-hotfix-v14 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v14] ok (" + str(len(routes)) + " route groups)")
PY
