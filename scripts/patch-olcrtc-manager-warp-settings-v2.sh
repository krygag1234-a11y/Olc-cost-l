#!/usr/bin/env bash
# WARP settings v2: mode/autoconnect/plus/license in panel settings.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'unsafe warp mode' "$MAIN_GO" && { echo "[patch-warp-settings-v2] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old_get = '''func warpSettingsGet() map[string]any {
\tenv := readPanelEnvMap()
\tproxy := env["OLCRTC_WARP_PROXY"]
\tif strings.TrimSpace(proxy) == "" {
\t\tproxy = "127.0.0.1:40000"
\t}
\treturn map[string]any{
\t\t"proxy":              proxy,
\t\t"installed":          componentInstalled("warp"),
\t\t"connected":          warpConnected(),
\t\t"conflicts_with_tor": true,
\t\t"profile_enabled":    deployProfileComponent("warp"),
\t}
}'''
new_get = '''func warpSettingsGet() map[string]any {
\tenv := readPanelEnvMap()
\tproxy := env["OLCRTC_WARP_PROXY"]
\tif strings.TrimSpace(proxy) == "" {
\t\tproxy = "127.0.0.1:40000"
\t}
\tmode := env["OLCRTC_WARP_MODE"]
\tif strings.TrimSpace(mode) == "" {
\t\tmode = "proxy"
\t}
\tlicense := env["OLCRTC_WARP_LICENSE"]
\tautoconnect := env["OLCRTC_WARP_AUTOCONNECT"] != "0"
\tplus := env["OLCRTC_WARP_PLUS"] == "1"
\treturn map[string]any{
\t\t"proxy":              proxy,
\t\t"mode":               mode,
\t\t"license_key":        license,
\t\t"autoconnect":        autoconnect,
\t\t"warp_plus":          plus,
\t\t"installed":          componentInstalled("warp"),
\t\t"connected":          warpConnected(),
\t\t"conflicts_with_tor": true,
\t\t"profile_enabled":    deployProfileComponent("warp"),
\t}
}'''
if old_get in t:
    t = t.replace(old_get, new_get, 1)

old_put = '''func warpSettingsPut(body map[string]any) error {
\tif v, ok := body["proxy"].(string); ok {
\t\tif err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
\t\t\treturn err
\t\t}
\t}
\treturn nil
}'''
new_put = '''func warpSettingsPut(body map[string]any) error {
\tif v, ok := body["proxy"].(string); ok {
\t\tif err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
\t\t\treturn err
\t\t}
\t}
\tif v, ok := body["mode"].(string); ok {
\t\tm := strings.TrimSpace(v)
\t\tif m == "" {
\t\t\tm = "proxy"
\t\t}
\t\tif m != "proxy" {
\t\t\treturn fmt.Errorf("unsafe warp mode %q blocked; only proxy mode is allowed", m)
\t\t}
\t\tif err := setPanelEnvKey("OLCRTC_WARP_MODE", m); err != nil {
\t\t\treturn err
\t\t}
\t}
\tif v, ok := body["license_key"].(string); ok {
\t\tif err := setPanelEnvKey("OLCRTC_WARP_LICENSE", strings.TrimSpace(v)); err != nil {
\t\t\treturn err
\t\t}
\t}
\tif v, ok := body["autoconnect"].(bool); ok {
\t\tval := "0"
\t\tif v {
\t\t\tval = "1"
\t\t}
\t\tif err := setPanelEnvKey("OLCRTC_WARP_AUTOCONNECT", val); err != nil {
\t\t\treturn err
\t\t}
\t}
\tif v, ok := body["warp_plus"].(bool); ok {
\t\tval := "0"
\t\tif v {
\t\t\tval = "1"
\t\t}
\t\tif err := setPanelEnvKey("OLCRTC_WARP_PLUS", val); err != nil {
\t\t\treturn err
\t\t}
\t}
\treturn nil
}'''
if old_put in t:
    t = t.replace(old_put, new_put, 1)

for key in ["OLCRTC_WARP_MODE", "OLCRTC_WARP_LICENSE", "OLCRTC_WARP_AUTOCONNECT", "OLCRTC_WARP_PLUS"]:
    if key not in t:
        t = t.replace('"OLCRTC_WARP_PROXY":  true,', f'"OLCRTC_WARP_PROXY":  true,\\n\\t\\t"{key}": true,', 1)

p.write_text(t)
print("[patch-warp-settings-v2] ok")
PY
