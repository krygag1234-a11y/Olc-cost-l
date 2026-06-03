#!/usr/bin/env bash
# API /api/bridges/status — health, active bridges, Tor connectivity.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q '"/api/bridges/status"' "$MAIN_GO" && { echo "[patch-bridge-status-api] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Add route
route = '\thandler.Handle("/api/bridges/status", adminAuth(http.HandlerFunc(bridgeStatusHandler)))\n'
anchors = [
    '\thandler.Handle("/api/settings/bridges", adminAuth(componentSettingsHandler("bridges")))',
    '\thandler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler())))',
]
if '"/api/bridges/status"' not in t:
    for anchor in anchors:
        if anchor in t:
            t = t.replace(anchor, route + anchor, 1)
            break

helpers = r'''
const torBridgeHealthPath = "/var/lib/olcrtc/tor-bridge-health.tsv"
const torBridgesConfPath = "/etc/tor/bridges.conf"
const torMonitorStatePath = "/var/lib/olcrtc/tor-monitor-state.txt"

func bridgeStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Check Tor connectivity
	torOk := false
	if resp, err := http.Get("socks5://127.0.0.1:9050"); err == nil {
		resp.Body.Close()
		torOk = true
	}

	// Read active bridges from torrc
	activeBridges := []map[string]any{}
	if b, err := os.ReadFile(torBridgesConfPath); err == nil {
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if !strings.HasPrefix(line, "Bridge ") {
				continue
			}
			parts := strings.Fields(line)
			if len(parts) < 3 {
				continue
			}
			bridgeType := parts[1]
			fp := ""
			if len(parts) > 2 {
				fp = parts[2]
			}
			activeBridges = append(activeBridges, map[string]any{
				"type":        bridgeType,
				"fingerprint": fp,
			})
		}
	}

	// Read health stats
	healthMap := map[string]map[string]any{}
	if b, err := os.ReadFile(torBridgeHealthPath); err == nil {
		lines := strings.Split(string(b), "\n")
		for i, line := range lines {
			if i == 0 || line == "" {
				continue // skip header
			}
			fields := strings.Split(line, "\t")
			if len(fields) < 7 {
				continue
			}
			fp := fields[0]
			healthMap[fp] = map[string]any{
				"ok_total":    fields[1],
				"fail_total":  fields[2],
				"fail_streak": fields[3],
				"last_status": fields[6],
			}
		}
	}

	// Monitor state (fail count)
	monitorFails := 0
	if b, err := os.ReadFile(torMonitorStatePath); err == nil {
		for _, line := range strings.Split(string(b), "\n") {
			if strings.HasPrefix(line, "fails=") {
				fmt.Sscanf(line, "fails=%d", &monitorFails)
			}
		}
	}

	// Attach health to active bridges
	for i := range activeBridges {
		fp := activeBridges[i]["fingerprint"].(string)
		if health, ok := healthMap[fp]; ok {
			activeBridges[i]["health"] = health
		}
	}

	writeJSON(w, map[string]any{
		"tor_ok":          torOk,
		"active_bridges":  activeBridges,
		"monitor_fails":   monitorFails,
		"pool_size":       len(healthMap),
	})
}

'''

if 'func bridgeStatusHandler' not in t:
    t = t.replace('func componentSettingsGet(name string)', helpers + 'func componentSettingsGet(name string)', 1)

p.write_text(t)
print("[patch-bridge-status-api] ok")
PY
