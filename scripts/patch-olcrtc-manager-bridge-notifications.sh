#!/usr/bin/env bash
# Push bridge errors to notifications when monitor fails > 2.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'checkBridgeHealth' "$MAIN_GO" && { echo "[patch-bridge-notifications] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helper = r'''
func pushNotification(data map[string]any) {
	var list []map[string]any
	readJSONFile(panelNotifFile, &list)

	// Deduplicate by ID
	if id, ok := data["id"].(string); ok && id != "" {
		for i := range list {
			if existingID, ok := list[i]["id"].(string); ok && existingID == id {
				return // already exists
			}
		}
	}

	data["timestamp"] = time.Now().Unix()
	if _, ok := data["read"]; !ok {
		data["read"] = false
	}
	list = append([]map[string]any{data}, list...)

	// Keep last 100
	if len(list) > 100 {
		list = list[:100]
	}

	b, _ := json.MarshalIndent(list, "", "  ")
	_ = os.WriteFile(panelNotifFile, b, 0644)
}

func checkBridgeHealth() {
	monitorStatePath := "/var/lib/olcrtc/tor-monitor-state.txt"
	b, err := os.ReadFile(monitorStatePath)
	if err != nil {
		return
	}
	fails := 0
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "fails=") {
			fmt.Sscanf(line, "fails=%d", &fails)
		}
	}
	if fails > 2 {
		pushNotification(map[string]any{
			"id":       "bridge-health-warning",
			"type":     "warning",
			"source":   "tor",
			"title":    "Проблемы с Tor мостами",
			"message":  fmt.Sprintf("Tor недоступен (%d попытки). Рекомендуется ротация мостов.", fails),
			"action":   "open-bridge-settings",
			"expires":  time.Now().Add(1 * time.Hour).Unix(),
		})
	}
}

'''

if 'func checkBridgeHealth' not in t:
    # Add helper before main
    t = t.replace('func main() {', helper + 'func main() {', 1)

# Add periodic check in background
if 'go checkBridgeHealth' not in t and 'func main()' in t:
    main_block = 'log.Fatal(handler.ListenAndServe())'
    replacement = '''go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			checkBridgeHealth()
		}
	}()
	log.Fatal(handler.ListenAndServe())'''
    if main_block in t:
        t = t.replace(main_block, replacement, 1)

p.write_text(t)
print("[patch-bridge-notifications] ok")
PY
