#!/usr/bin/env bash
# Bridge pool refresh: --fetch, webtunnel install, job status JSON for UI polling.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'bridgePoolStatusFile' "$MAIN_GO" && { echo "[patch-bridge-pool-job] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if 'bridgePoolStatusFile' not in t.split('bridgeCronPath')[0]:
    t = t.replace(
        'bridgeCronPath     = "/etc/cron.d/olcrtc-bridge-pool"',
        'bridgeCronPath     = "/etc/cron.d/olcrtc-bridge-pool"\n\tbridgePoolStatusFile = "/var/lib/olcrtc/bridge-pool-status.json"',
        1,
    )

helpers = r'''
func readBridgePoolStatus() map[string]any {
	var st map[string]any
	if readJSONFile(bridgePoolStatusFile, &st) {
		return st
	}
	return map[string]any{"status": "idle"}
}

func writeBridgePoolStatus(st map[string]any) {
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return
	}
	_ = os.MkdirAll(filepath.Dir(bridgePoolStatusFile), 0755)
	_ = os.WriteFile(bridgePoolStatusFile, b, 0644)
}

func tailLogFile(path string, n int) []string {
	lines, err := tailFileLines(path, n)
	if err != nil {
		return nil
	}
	return lines
}

'''

if 'func readBridgePoolStatus' not in t:
    t = t.replace('func bridgePoolStats()', helpers + 'func bridgePoolStats()', 1)

old_run = '''func runBridgePoolRefresh(types string) {
	script := filepath.Join(olcRepoRoot(), "scripts/tor-bridge-pool.sh")
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
		defer cancel()
		cmd := exec.CommandContext(ctx, "bash", script, "--types", types)
		cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
		_, _ = cmd.CombinedOutput()
	}()
}'''

new_run = '''func runBridgePoolRefresh(types string) {
	types = strings.TrimSpace(types)
	if types == "" {
		types = "obfs4,webtunnel"
	}
	writeBridgePoolStatus(map[string]any{
		"status":     "running",
		"started_at": time.Now().Format(time.RFC3339),
		"types":      types,
		"log_path":   "/var/log/olcrtc-bridge-pool.log",
	})
	go func() {
		repo := olcRepoRoot()
		script := filepath.Join(repo, "scripts/tor-bridge-pool.sh")
		if strings.Contains(strings.ToLower(types), "webtunnel") {
			wt := filepath.Join(repo, "scripts/install-tor-pluggable-transports.sh")
			if _, err := os.Stat(wt); err == nil {
				_ = exec.Command("bash", wt).Run()
			}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 25*time.Minute)
		defer cancel()
		cmd := exec.CommandContext(ctx, "bash", script, "--fetch", "--types", types)
		cmd.Env = append(os.Environ(),
			"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin",
			"BRIDGE_TYPES="+types,
			"FETCH_MAX_AGE_SEC=0",
			"LOG_FILE=/var/log/olcrtc-bridge-pool.log",
		)
		out, err := cmd.CombinedOutput()
		st := map[string]any{
			"status":           "done",
			"finished_at":      time.Now().Format(time.RFC3339),
			"types":            types,
			"pool_stats":       bridgePoolStats(),
			"webtunnel_client": fileExists("/usr/bin/webtunnel-client"),
			"log_tail":         tailLogFile("/var/log/olcrtc-bridge-pool.log", 40),
		}
		if err != nil {
			st["status"] = "error"
			st["error"] = strings.TrimSpace(err.Error())
			if len(out) > 0 {
				st["output"] = string(out)
			}
		}
		writeBridgePoolStatus(st)
	}()
}'''

if old_run in t:
    t = t.replace(old_run, new_run, 1)

# Include pool_job in bridges GET
needle = '"pool_stats":      bridgePoolStats(),'
if '"pool_job":' not in t:
    t = t.replace(
        needle,
        '"pool_job":        readBridgePoolStatus(),\n\t\t\t"pool_stats":      bridgePoolStats(),',
        1,
    )

old_handler = '''		case http.MethodPut:
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if err := componentSettingsPut(name, body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			componentSettingsAfterSave(name, body)
			writeJSON(w, map[string]string{"status": "ok"})'''

new_handler = '''		case http.MethodPut:
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if name == "bridges" {
				if action, ok := body["action"].(string); ok && action == "refresh_pool" {
					types := "obfs4,webtunnel"
					if v, ok := body["types"].(string); ok && strings.TrimSpace(v) != "" {
						types = strings.TrimSpace(v)
					}
					runBridgePoolRefresh(types)
					writeJSON(w, map[string]any{"status": "ok", "pool_job": readBridgePoolStatus()})
					return
				}
			}
			if err := componentSettingsPut(name, body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			componentSettingsAfterSave(name, body)
			writeJSON(w, map[string]string{"status": "ok"})'''

if old_handler in t:
    t = t.replace(old_handler, new_handler, 1)

# Avoid double-handling refresh in componentSettingsPut
t = t.replace(
    '''		if action, ok := body["action"].(string); ok && action == "refresh_pool" {
			types := "obfs4,webtunnel"
			if v, ok := body["types"].(string); ok && strings.TrimSpace(v) != "" {
				types = strings.TrimSpace(v)
			}
			runBridgePoolRefresh(types)
			return nil
		}''',
    '',
    1,
)

p.write_text(t)
print("[patch-bridge-pool-job] ok (runBridgePoolRefresh + status)")
PY
