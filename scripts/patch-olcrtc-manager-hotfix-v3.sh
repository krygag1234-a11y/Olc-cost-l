#!/usr/bin/env bash
# Hotfix v3: cleanup misplaced warp block and ensure warp PUT case.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Remove any illegal warp block inside featureLogPaths.
t = re.sub(
    r'(\nfunc featureLogPaths\(name string\) \[\]string \{\n(?:.|\n)*?case "tor":\n\t\treturn \[\]string\{"/var/log/olcrtc-healthcheck.log", "/var/log/tor/log"\}\n)\n\tcase "warp":(?:.|\n)*?\n\t\treturn nil\n\tcase "split":',
    r'\1\n\tcase "split":',
    t,
    count=1,
)

# Ensure warp is allowed in settings handler.
t = t.replace(
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true}',
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true, "warp": true}',
    1,
)

# Ensure project status route exists.
if '/api/project/status' not in t:
    anchor = '\thandler.Handle("/api/settings", adminAuth(http.HandlerFunc(settingsHandler(configPath, portOverride))))\n'
    if anchor in t:
        t = t.replace(anchor, anchor + '\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))\n', 1)

# Ensure warp GET in componentSettingsGet.
get_start = t.find("func componentSettingsGet(name string)")
get_end = t.find("func patchTorrcKey(")
get_slice = t[get_start:get_end] if get_start >= 0 and get_end > get_start else ""
if 'case "warp":' not in get_slice:
    ins = '\tcase "bridges":'
    block = '''
\tcase "warp":
\t\tenv := readPanelEnvMap()
\t\tinstalled := fileExists("/usr/bin/warp-cli") || fileExists("/usr/local/bin/warp-cli")
\t\tconnected := false
\t\tif installed {
\t\t\tout, _ := exec.Command("warp-cli", "status").CombinedOutput()
\t\t\ts := strings.ToLower(string(out))
\t\t\tconnected = strings.Contains(s, "connected")
\t\t}
\t\tmode := strings.TrimSpace(env["OLCRTC_WARP_MODE"])
\t\tif mode == "" {
\t\t\tmode = "proxy"
\t\t}
\t\treturn map[string]any{
\t\t\t"proxy":           firstNonEmpty(strings.TrimSpace(env["OLCRTC_WARP_PROXY"]), "127.0.0.1:40000"),
\t\t\t"mode":            mode,
\t\t\t"autoconnect":     env["OLCRTC_WARP_AUTOCONNECT"] != "0",
\t\t\t"warp_plus":       env["OLCRTC_WARP_PLUS"] == "1" || strings.EqualFold(env["OLCRTC_WARP_PLUS"], "true"),
\t\t\t"license_key":     strings.TrimSpace(env["OLCRTC_WARP_LICENSE"]),
\t\t\t"installed":       installed,
\t\t\t"connected":       connected,
\t\t\t"profile_enabled": readFeatureFlags()["warp"],
\t\t}, nil
'''
    if ins in t:
        t = t.replace(ins, block + ins, 1)

# Ensure helper exists.
if "func firstNonEmpty(" not in t:
    t = t.replace(
        "func componentSettingsGet(name string)",
        'func firstNonEmpty(v, fallback string) string {\n\tv = strings.TrimSpace(v)\n\tif v != "" {\n\t\treturn v\n\t}\n\treturn fallback\n}\n\nfunc componentSettingsGet(name string)',
        1,
    )

# Ensure warp PUT in componentSettingsPut.
put_start = t.find("func componentSettingsPut(name string, body map[string]any) error {")
put_end = t.find("// component-settings-v3")
put_slice = t[put_start:put_end] if put_start >= 0 and put_end > put_start else ""
if 'case "warp":' not in put_slice:
    anchor = '\tcase "tor":'
    block = '''
\tcase "warp":
\t\tif v, ok := body["proxy"].(string); ok {
\t\t\tif err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
\t\t\t\treturn err
\t\t\t}
\t\t}
\t\tif v, ok := body["mode"].(string); ok {
\t\t\tmv := strings.TrimSpace(v)
\t\t\tif mv == "" {
\t\t\t\tmv = "proxy"
\t\t\t}
\t\t\tif err := setPanelEnvKey("OLCRTC_WARP_MODE", mv); err != nil {
\t\t\t\treturn err
\t\t\t}
\t\t}
\t\tif v, ok := body["autoconnect"].(bool); ok {
\t\t\tval := "0"
\t\t\tif v {
\t\t\t\tval = "1"
\t\t\t}
\t\t\tif err := setPanelEnvKey("OLCRTC_WARP_AUTOCONNECT", val); err != nil {
\t\t\t\treturn err
\t\t\t}
\t\t}
\t\tif v, ok := body["warp_plus"].(bool); ok {
\t\t\tval := "0"
\t\t\tif v {
\t\t\t\tval = "1"
\t\t\t}
\t\t\tif err := setPanelEnvKey("OLCRTC_WARP_PLUS", val); err != nil {
\t\t\t\treturn err
\t\t\t}
\t\t}
\t\tif v, ok := body["license_key"].(string); ok {
\t\t\tif err := setPanelEnvKey("OLCRTC_WARP_LICENSE", strings.TrimSpace(v)); err != nil {
\t\t\t\treturn err
\t\t\t}
\t\t}
\t\treturn nil
'''
    if anchor in put_slice:
        put_slice = put_slice.replace(anchor, block + anchor, 1)
        t = t[:put_start] + put_slice + t[put_end:]

if "olc-manager-hotfix-v3" not in t:
    t = t.replace("/* olc-manager-hotfix-v2 */", "/* olc-manager-hotfix-v2 */\n/* olc-manager-hotfix-v3 */", 1)

p.write_text(t)
print("[patch-manager-hotfix-v3] ok")
PY
