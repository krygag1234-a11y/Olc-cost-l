#!/usr/bin/env bash
# Hotfix v2: restore missing project/settings routes and warp settings backend.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v2' "$MAIN_GO" && { echo "[patch-manager-hotfix-v2] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Ensure project status route exists.
if '/api/project/status' not in t:
    anchor = '\thandler.Handle("/api/settings", adminAuth(http.HandlerFunc(settingsHandler(configPath, portOverride))))\n'
    add = '\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))\n'
    if anchor in t:
        t = t.replace(anchor, anchor + add, 1)

# Component settings handler should include warp.
t = t.replace(
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true}',
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true, "warp": true}',
    1,
)

# Add warp settings GET block if missing.
if 'case "warp":' not in t[t.find("func componentSettingsGet"):t.find("func patchTorrcKey")]:
    insert_before = '\tcase "bridges":'
    block = r'''
	case "warp":
		env := readPanelEnvMap()
		installed := fileExists("/usr/bin/warp-cli") || fileExists("/usr/local/bin/warp-cli")
		connected := false
		if installed {
			out, _ := exec.Command("warp-cli", "status").CombinedOutput()
			s := strings.ToLower(string(out))
			connected = strings.Contains(s, "connected")
		}
		mode := strings.TrimSpace(env["OLCRTC_WARP_MODE"])
		if mode == "" {
			mode = "proxy"
		}
		return map[string]any{
			"proxy":           firstNonEmpty(strings.TrimSpace(env["OLCRTC_WARP_PROXY"]), "127.0.0.1:40000"),
			"mode":            mode,
			"autoconnect":     env["OLCRTC_WARP_AUTOCONNECT"] != "0",
			"warp_plus":       env["OLCRTC_WARP_PLUS"] == "1" || strings.EqualFold(env["OLCRTC_WARP_PLUS"], "true"),
			"license_key":     strings.TrimSpace(env["OLCRTC_WARP_LICENSE"]),
			"installed":       installed,
			"connected":       connected,
			"profile_enabled": readFeatureFlags()["warp"],
		}, nil
'''
    if insert_before in t:
        t = t.replace(insert_before, block + insert_before, 1)

# Add warp settings PUT block if missing.
put_start = t.find("func componentSettingsPut")
put_end = t.find("// component-settings-v3")
put_slice = t[put_start:put_end] if put_start >= 0 and put_end > put_start else ""
if 'case "warp":' not in put_slice:
    insert_before = '\tcase "split":'
    block = r'''
	case "warp":
		if v, ok := body["proxy"].(string); ok {
			if err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
				return err
			}
		}
		if v, ok := body["mode"].(string); ok {
			mv := strings.TrimSpace(v)
			if mv == "" {
				mv = "proxy"
			}
			if err := setPanelEnvKey("OLCRTC_WARP_MODE", mv); err != nil {
				return err
			}
		}
		if v, ok := body["autoconnect"].(bool); ok {
			val := "0"
			if v {
				val = "1"
			}
			if err := setPanelEnvKey("OLCRTC_WARP_AUTOCONNECT", val); err != nil {
				return err
			}
		}
		if v, ok := body["warp_plus"].(bool); ok {
			val := "0"
			if v {
				val = "1"
			}
			if err := setPanelEnvKey("OLCRTC_WARP_PLUS", val); err != nil {
				return err
			}
		}
		if v, ok := body["license_key"].(string); ok {
			if err := setPanelEnvKey("OLCRTC_WARP_LICENSE", strings.TrimSpace(v)); err != nil {
				return err
			}
		}
		return nil
'''
    if insert_before in t:
        t = t.replace(insert_before, block + insert_before, 1)

# Helper for defaults.
if "func firstNonEmpty(" not in t:
    helper = '''
func firstNonEmpty(v, fallback string) string {
\tv = strings.TrimSpace(v)
\tif v != "" {
\t\treturn v
\t}
\treturn fallback
}

'''
    t = t.replace("func componentSettingsGet(name string)", helper + "func componentSettingsGet(name string)", 1)

if "olc-manager-hotfix-v2" not in t:
    t = t.replace("/* olc-manager-hotfix-v1 */", "/* olc-manager-hotfix-v1 */\n/* olc-manager-hotfix-v2 */", 1)

p.write_text(t)
print("[patch-manager-hotfix-v2] ok")
PY
