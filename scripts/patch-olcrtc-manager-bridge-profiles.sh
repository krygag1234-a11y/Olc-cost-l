#!/usr/bin/env bash
# Bridge profiles in GET/PUT /api/settings/bridges + pool refresh action.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'bridgeProfilesPath = "/var/lib/olcrtc/bridge-profiles.json"' "$MAIN_GO" && { echo "[patch-bridge-profiles] already applied"; exit 0; }

python3 - "$MAIN_GO" "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
repo = Path(sys.argv[2])
t = p.read_text()

const_old = '''const (
	panelUpdateLock  = "/var/lib/olcrtc/panel-update.lock"
	panelUpdateStatus = "/var/lib/olcrtc/panel-update-status.json"
	panelJobsDir     = "/var/lib/olcrtc/panel-jobs"
	panelNotifFile   = "/var/lib/olcrtc/notifications.json"
)'''
const_new = '''const (
	panelUpdateLock    = "/var/lib/olcrtc/panel-update.lock"
	panelUpdateStatus  = "/var/lib/olcrtc/panel-update-status.json"
	panelJobsDir       = "/var/lib/olcrtc/panel-jobs"
	panelNotifFile     = "/var/lib/olcrtc/notifications.json"
	bridgeProfilesPath = "/var/lib/olcrtc/bridge-profiles.json"
	bridgeCronPath     = "/etc/cron.d/olcrtc-bridge-pool"
)'''
if 'bridgeProfilesPath =' not in t and const_old in t:
    t = t.replace(const_old, const_new, 1)

helpers = r'''
func defaultBridgeProfiles() map[string]any {
	return map[string]any{
		"active_profile": "system",
		"system": map[string]any{
			"id":           "system",
			"label":        "Оригинальный",
			"types":        "obfs4,webtunnel",
			"auto_update":  true,
			"readonly":     true,
		},
		"profiles": []any{},
	}
}

func readBridgeProfiles() map[string]any {
	out := defaultBridgeProfiles()
	var stored map[string]any
	if readJSONFile(bridgeProfilesPath, &stored) {
		for k, v := range stored {
			out[k] = v
		}
	}
	return out
}

func writeBridgeProfiles(data map[string]any) error {
	if err := os.MkdirAll(filepath.Dir(bridgeProfilesPath), 0755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(bridgeProfilesPath, b, 0644)
}

func bridgePoolStats() map[string]any {
	stats := map[string]any{"obfs4": 0, "webtunnel": 0, "other": 0, "total": 0}
	pool := "/var/lib/olcrtc/tor-bridges-pool.txt"
	b, err := os.ReadFile(pool)
	if err != nil {
		return stats
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "Bridge ") {
			continue
		}
		stats["total"] = stats["total"].(int) + 1
		low := strings.ToLower(line)
		switch {
		case strings.Contains(low, " webtunnel "):
			stats["webtunnel"] = stats["webtunnel"].(int) + 1
		case strings.Contains(low, " obfs4 "):
			stats["obfs4"] = stats["obfs4"].(int) + 1
		default:
			stats["other"] = stats["other"].(int) + 1
		}
	}
	return stats
}

func setBridgeAutoCron(enabled bool) {
	if enabled {
		cron := "15 3 * * * root " + filepath.Join(olcRepoRoot(), "scripts/tor-bridge-pool.sh") + " --types obfs4,webtunnel >>/var/log/olcrtc-bridge-pool.log 2>&1\n"
		_ = writeTextFile(bridgeCronPath, cron)
	} else {
		_ = os.Remove(bridgeCronPath)
	}
}

func runBridgePoolRefresh(types string) {
	script := filepath.Join(olcRepoRoot(), "scripts/tor-bridge-pool.sh")
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
		defer cancel()
		cmd := exec.CommandContext(ctx, "bash", script, "--types", types)
		cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
		_, _ = cmd.CombinedOutput()
	}()
}

'''

# Replace bridges case in componentSettingsGet
old_bridges = '''	case "bridges":
		return map[string]any{
			"bridges_conf": readTextFile("/etc/tor/bridges.conf"),
			"webtunnel":    fileExists("/usr/bin/webtunnel-client"),
		}, nil'''

new_bridges = '''	case "bridges":
		bp := readBridgeProfiles()
		active := map[string]any{}
		if id, ok := bp["active_profile"].(string); ok {
			if id == "system" {
				active = bp["system"].(map[string]any)
			} else if profs, ok := bp["profiles"].([]any); ok {
				for _, pr := range profs {
					m, _ := pr.(map[string]any)
					if m != nil && m["id"] == id {
						active = m
						break
					}
				}
			}
		}
		return map[string]any{
			"bridges_conf":    readTextFile("/etc/tor/bridges.conf"),
			"webtunnel":       fileExists("/usr/bin/webtunnel-client"),
			"pool_stats":      bridgePoolStats(),
			"profiles":        bp,
			"active_profile":  active,
		}, nil'''

if old_bridges in t:
    t = t.replace(old_bridges, new_bridges, 1)

# Extend componentSettingsPut bridges + action
if 'bridge_profiles' not in t:
    t = t.replace(
        '''	case "bridges":
		if v, ok := body["custom_bridge"].(string); ok && strings.TrimSpace(v) != "" {''',
        '''	case "bridges":
		if action, ok := body["action"].(string); ok && action == "refresh_pool" {
			types := "obfs4,webtunnel"
			if v, ok := body["types"].(string); ok && strings.TrimSpace(v) != "" {
				types = strings.TrimSpace(v)
			}
			runBridgePoolRefresh(types)
			return nil
		}
		if raw, ok := body["bridge_profiles"].(map[string]any); ok {
			cur := readBridgeProfiles()
			for k, v := range raw {
				if k == "system" {
					if sm, ok := v.(map[string]any); ok {
						if sys, ok := cur["system"].(map[string]any); ok {
							if t, ok := sm["types"].(string); ok {
								sys["types"] = t
							}
							if au, ok := sm["auto_update"].(bool); ok {
								sys["auto_update"] = au
								setBridgeAutoCron(au)
							}
							cur["system"] = sys
						}
					}
					continue
				}
				cur[k] = v
			}
			if ap, ok := body["active_profile"].(string); ok {
				cur["active_profile"] = ap
			}
			return writeBridgeProfiles(cur)
		}
		if v, ok := body["custom_bridge"].(string); ok && strings.TrimSpace(v) != "" {''',
        1,
    )

if 'func readBridgeProfiles' not in t:
    t = t.replace('func componentSettingsGet(name string)', helpers + 'func componentSettingsGet(name string)', 1)

p.write_text(t)
print("[patch-bridge-profiles] ok")
PY
