#!/usr/bin/env bash
# GET/PUT /api/notification-settings — autodetect preferences.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q '"/api/notification-settings"' "$MAIN_GO" && { echo "[patch-notification-settings] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

route = '\thandler.Handle("/api/notification-settings", adminAuth(http.HandlerFunc(notificationSettingsHandler)))\n'
anchors = [
    '\thandler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler())))',
    '\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))',
]
if '"/api/notification-settings"' not in t:
    for anchor in anchors:
        if anchor in t:
            t = t.replace(anchor, route + anchor, 1)
            break

helpers = r'''
const notificationSettingsPath = "/etc/olcrtc-manager/notification-settings.json"

func defaultNotificationSettings() map[string]any {
	return map[string]any{
		"enabled":           true,
		"scan_interval_sec": 60,
		"min_severity":      "warning",
		"show_toast":        true,
		"sources": map[string]bool{
			"instance": true,
			"olcrtc":   true,
			"tor":      true,
			"zapret":   true,
			"panel":    true,
			"split":    true,
		},
	}
}

func readNotificationSettings() map[string]any {
	out := defaultNotificationSettings()
	var stored map[string]any
	if readJSONFile(notificationSettingsPath, &stored) {
		for k, v := range stored {
			out[k] = v
		}
	}
	return out
}

func notificationSettingsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, map[string]any{"settings": readNotificationSettings()})
	case http.MethodPut:
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		cur := readNotificationSettings()
		for k, v := range body {
			cur[k] = v
		}
		b, _ := json.MarshalIndent(cur, "", "  ")
		if err := os.WriteFile(notificationSettingsPath, b, 0644); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, map[string]any{"status": "ok", "settings": cur})
	default:
		w.Header().Set("Allow", "GET, PUT")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

'''

if 'func notificationSettingsHandler' not in t:
    t = t.rstrip() + "\n" + helpers

p.write_text(t)
print("[patch-notification-settings] ok")
PY
