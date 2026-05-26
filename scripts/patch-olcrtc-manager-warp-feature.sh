#!/usr/bin/env bash
# WARP as first-class feature: toggle, settings, capabilities, stack status.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'OLCRTC_ENABLE_WARP' "$MAIN_GO" && { echo "[patch-warp-feature] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

t = t.replace(
    'var featureNames = []string{"zapret", "tor", "split", "webtunnel", "olcrtc"}',
    'var featureNames = []string{"zapret", "tor", "split", "webtunnel", "warp", "olcrtc"}',
    1,
)

for old, new in [
    (
        '\t\tcase "OLCRTC_ENABLE_WEBTUNNEL":\n\t\t\tflags["webtunnel"] = val != "0"\n\t\t}\n\t}\n\treturn flags\n}',
        '\t\tcase "OLCRTC_ENABLE_WEBTUNNEL":\n\t\t\tflags["webtunnel"] = val != "0"\n\t\tcase "OLCRTC_ENABLE_WARP":\n\t\t\tflags["warp"] = val != "0"\n\t\t}\n\t}\n\treturn flags\n}',
    ),
    (
        'flags := map[string]bool{"zapret": true, "tor": true, "split": true, "webtunnel": true}',
        'flags := map[string]bool{"zapret": true, "tor": true, "split": true, "webtunnel": true, "warp": false}',
    ),
    (
        '\t\tcase "OLCRTC_ENABLE_WEBTUNNEL":\n\t\t\tflags["webtunnel"] = enabled\n\t\t}\n\t}\n\treturn flags\n}',
        '\t\tcase "OLCRTC_ENABLE_WEBTUNNEL":\n\t\t\tflags["webtunnel"] = enabled\n\t\tcase "OLCRTC_ENABLE_WARP":\n\t\t\tflags["warp"] = enabled\n\t\t}\n\t}\n\treturn flags\n}',
    ),
]:
    if old in t:
        t = t.replace(old, new, 1)

ci = t.split('func componentInstalled')
if len(ci) > 1 and 'case "warp":' not in ci[1].split('func loadFeatureFlagsMap')[0]:
    t = t.replace(
        '''\tcase "bridges", "webtunnel":
\t\tif _, err := os.Stat("/usr/bin/webtunnel-client"); err == nil {
\t\t\treturn true
\t\t}
\t\tif _, err := os.Stat("/etc/tor/bridges.conf"); err == nil {
\t\t\treturn true
\t\t}
\t\treturn false
\tdefault:''',
        '''\tcase "bridges", "webtunnel":
\t\tif _, err := os.Stat("/usr/bin/webtunnel-client"); err == nil {
\t\t\treturn true
\t\t}
\t\tif _, err := os.Stat("/etc/tor/bridges.conf"); err == nil {
\t\t\treturn true
\t\t}
\t\treturn false
\tcase "warp":
\t\t_, err := exec.LookPath("warp-cli")
\t\treturn err == nil
\tdefault:''',
        1,
    )

helpers = r'''
func deployProfileComponent(key string) bool {
	b, err := os.ReadFile("/etc/olcrtc-manager/deploy-profile.json")
	if err != nil {
		return false
	}
	var v struct {
		Components map[string]bool `json:"components"`
	}
	if json.Unmarshal(b, &v) != nil {
		return false
	}
	return v.Components[key]
}

func warpConnected() bool {
	cmd := exec.Command("warp-cli", "status")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(out)), "connected")
}

func warpSettingsGet() map[string]any {
	env := readPanelEnvMap()
	proxy := env["OLCRTC_WARP_PROXY"]
	if strings.TrimSpace(proxy) == "" {
		proxy = "127.0.0.1:40000"
	}
	return map[string]any{
		"proxy":              proxy,
		"installed":          componentInstalled("warp"),
		"connected":          warpConnected(),
		"conflicts_with_tor": true,
		"profile_enabled":    deployProfileComponent("warp"),
	}
}

func warpSettingsPut(body map[string]any) error {
	if v, ok := body["proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	return nil
}

'''

if 'func warpSettingsGet' not in t:
    t = t.replace('func readPanelEnvMap() map[string]string {', helpers + 'func readPanelEnvMap() map[string]string {', 1)

csg = t.split('func componentSettingsGet')
if len(csg) > 1 and 'case "warp":' not in csg[1].split('default:')[0]:
    t = t.replace(
        '\tcase "olcrtc":\n\t\treturn olcrtcSettingsGet(), nil\n\tcase "bridges":',
        '\tcase "olcrtc":\n\t\treturn olcrtcSettingsGet(), nil\n\tcase "warp":\n\t\treturn warpSettingsGet(), nil\n\tcase "bridges":',
        1,
    )

if 'if name == "warp"' not in t:
    t = t.replace(
        'func componentSettingsPut(name string, body map[string]any) error {\n\tif name == "olcrtc" {',
        'func componentSettingsPut(name string, body map[string]any) error {\n\tif name == "warp" {\n\t\treturn warpSettingsPut(body)\n\t}\n\tif name == "olcrtc" {',
        1,
    )

t = t.replace(
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true}',
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true, "warp": true}',
)

cap = t.split('components := map[string]comp{')
if len(cap) > 1 and '"warp":' not in cap[1].split('writeJSON(w, map[string]any{')[0]:
    t = t.replace(
        '''\t\t\t"bridges": {
\t\t\t\tInstalled: componentInstalled("bridges"), Enabled: flags["webtunnel"],
\t\t\t\tConfigurable: componentInstalled("tor"), Label: "Мосты",
\t\t\t},
\t\t}''',
        '''\t\t\t"bridges": {
\t\t\t\tInstalled: componentInstalled("bridges"), Enabled: flags["webtunnel"],
\t\t\t\tConfigurable: componentInstalled("tor"), Label: "Мосты",
\t\t\t},
\t\t\t"warp": {
\t\t\t\tInstalled: componentInstalled("warp"), Enabled: flags["warp"],
\t\t\t\tConfigurable: componentInstalled("warp") || deployProfileComponent("warp"), Label: "WARP",
\t\t\t},
\t\t}''',
        1,
    )

flp = t.split('func featureLogPaths')
if len(flp) > 1 and 'case "warp":' not in flp[1].split('default:')[0]:
    t = t.replace(
        '\tcase "webtunnel":\n\t\treturn []string{"/var/log/olcrtc-bridge-pool.log", "/var/log/olcrtc-healthcheck.log"}',
        '\tcase "webtunnel":\n\t\treturn []string{"/var/log/olcrtc-bridge-pool.log", "/var/log/olcrtc-healthcheck.log"}\n\tcase "warp":\n\t\treturn []string{"/var/log/olcrtc-warp-install.log", "/var/log/syslog"}',
        1,
    )

if 'out["warp"]' not in t:
    t = t.replace(
        '\tout["webtunnel"] = "missing"',
        '\tout["warp"] = "missing"\n\tif _, err := exec.LookPath("warp-cli"); err == nil {\n\t\tcmd := exec.Command("warp-cli", "status")\n\t\tb, _ := cmd.CombinedOutput()\n\t\tout["warp"] = strings.TrimSpace(string(b))\n\t\tif len(out["warp"]) > 80 {\n\t\t\tout["warp"] = out["warp"][:80] + "..."\n\t\t}\n\t}\n\tout["webtunnel"] = "missing"',
        1,
    )

fts = t.split('func featuresToggleSucceeded')
if len(fts) > 1 and 'name == "warp"' not in fts[1].split('return false')[0]:
    t = t.replace(
        '\tif name == "tor" && !wantEnabled && !flags["tor"] {\n\t\treturn true\n\t}\n\treturn false',
        '\tif name == "tor" && !wantEnabled && !flags["tor"] {\n\t\treturn true\n\t}\n\tif name == "warp" && wantEnabled && flags["warp"] {\n\t\treturn true\n\t}\n\treturn false',
        1,
    )

# componentStackStatus: real warp state instead of optional placeholder
old_stack = '''\toptional := []string{"warp"}
\ton := 0
\ttotal := 0
\titems := []map[string]any{}
\tfor _, id := range []string{"zapret", "tor", "split", "bridges"} {
\ttotal++
\tenabled := flags[id]
\tif enabled {
\t\ton++
\t}
\titems = append(items, map[string]any{
\t\t"id": id, "label": labels[id], "enabled": enabled, "installed": installed[id],
\t})
\t}
\tfor _, id := range optional {
\titems = append(items, map[string]any{
\t\t"id": id, "label": "WARP", "enabled": flags[id], "installed": false, "optional": true,
\t})
\t}
\treturn map[string]any{
\t\t"enabled": on, "total": total, "items": items,
\t\t"note": "Сервисы стека Olc-cost-l (Zapret, Tor, Split, Мосты). WARP — опционально.",
\t}'''

new_stack = '''\ton := 0
\ttotal := 0
\titems := []map[string]any{}
\tfor _, id := range []string{"zapret", "tor", "split", "bridges"} {
\t\ttotal++
\t\tenabled := flags[id]
\t\tif id == "bridges" {
\t\t\tenabled = flags["webtunnel"]
\t\t}
\t\tif enabled {
\t\t\ton++
\t\t}
\t\titems = append(items, map[string]any{
\t\t\t"id": id, "label": labels[id], "enabled": enabled, "installed": installed[id],
\t\t})
\t}
\tif deployProfileComponent("warp") || componentInstalled("warp") {
\t\titems = append(items, map[string]any{
\t\t\t"id": "warp", "label": "WARP", "enabled": flags["warp"], "installed": componentInstalled("warp"),
\t\t})
\t}
\treturn map[string]any{
\t\t"enabled": on, "total": total, "items": items,
\t\t"note": "Сервисы стека Olc-cost-l. WARP и Tor взаимоисключают.",
\t}'''

if old_stack in t:
    t = t.replace(old_stack, new_stack, 1)

cah = t.split('func componentsActionHandler')
if 'deployProfileComponent("warp")' in t and len(cah) > 1 and '"warp": true' not in cah[1].split('writeJSON(w, map[string]any{')[0]:
    t = t.replace(
        'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true}',
        'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "warp": true}',
        1,
    )

p.write_text(t)
print("[patch-warp-feature] ok")
PY
