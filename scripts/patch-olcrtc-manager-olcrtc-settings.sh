#!/usr/bin/env bash
# GET/PUT /api/settings/olcrtc — panel.env tunables for olcrtc stack.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'func olcrtcSettingsGet' "$MAIN_GO" && { echo "[patch-olcrtc-settings] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Extend component handler allowed list
t = t.replace(
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true}',
    'allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true, "olcrtc": true}',
    1,
)

helpers = r'''
func readPanelEnvMap() map[string]string {
	out := map[string]string{}
	b, err := os.ReadFile("/etc/olcrtc-manager/panel.env")
	if err != nil {
		return out
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			out[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}
	return out
}

func setPanelEnvKey(key, val string) error {
	allowed := map[string]bool{
		"OLCRTC_JITSI_INSECURE_TLS": true,
		"OLCRTC_PUBLIC_URL":         true,
		"OLCRTC_DIRECT_DOMAINS":     true,
		"OLCRTC_DIRECT_CIDRS":       true,
		"OLCRTC_BLOCKED_TOR_DOMAINS": true,
		"OLCRTC_FORCE_TOR_DOMAINS":  true,
	}
	if !allowed[key] {
		return fmt.Errorf("key %q not allowed", key)
	}
	path := "/etc/olcrtc-manager/panel.env"
	var lines []string
	if b, err := os.ReadFile(path); err == nil {
		lines = strings.Split(string(b), "\n")
	}
	found := false
	prefix := key + "="
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), prefix) {
			lines[i] = key + "=" + val
			found = true
			break
		}
	}
	if !found {
		lines = append(lines, key+"="+val)
	}
	body := strings.Join(lines, "\n")
	if !strings.HasSuffix(body, "\n") {
		body += "\n"
	}
	return os.WriteFile(path, []byte(body), 0644)
}

func olcrtcSettingsGet() map[string]any {
	env := readPanelEnvMap()
	pins := readPins(olcRepoRoot())
	sha := ""
	if o, ok := pins["olcrtc"].(map[string]any); ok {
		if s, ok := o["pinned_sha"].(string); ok {
			sha = s
		}
	}
	return map[string]any{
		"jitsi_insecure_tls": env["OLCRTC_JITSI_INSECURE_TLS"] == "1",
		"public_url":         env["OLCRTC_PUBLIC_URL"],
		"direct_domains_file": env["OLCRTC_DIRECT_DOMAINS"],
		"direct_cidrs_file":   env["OLCRTC_DIRECT_CIDRS"],
		"blocked_tor_file":    env["OLCRTC_BLOCKED_TOR_DOMAINS"],
		"force_tor_file":      env["OLCRTC_FORCE_TOR_DOMAINS"],
		"olcrtc_branch":        "fix/all",
		"olcrtc_pinned_sha":  sha,
		"upstream_notes":     "",
	}
}

'''

# inject into componentSettingsGet switch
if 'case "olcrtc":' not in t:
    t = t.replace(
        '\tcase "bridges":\n\t\treturn map[string]any{',
        '\tcase "olcrtc":\n\t\treturn olcrtcSettingsGet(), nil\n\tcase "bridges":\n\t\treturn map[string]any{',
        1,
    )

put_helper = r'''
func olcrtcSettingsPut(body map[string]any) error {
	if v, ok := body["jitsi_insecure_tls"].(bool); ok {
		val := "0"
		if v {
			val = "1"
		}
		if err := setPanelEnvKey("OLCRTC_JITSI_INSECURE_TLS", val); err != nil {
			return err
		}
	}
	if v, ok := body["public_url"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_PUBLIC_URL", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	return nil
}
'''

if 'func olcrtcSettingsPut' not in t:
    idx = t.find('func componentSettingsPut')
    if idx > 0:
        t = t[:idx] + put_helper + "\n" + t[idx:]

parts = t.split('func componentSettingsPut')
if len(parts) > 1 and 'if name == "olcrtc"' not in parts[1][:400]:
    t = t.replace(
        'func componentSettingsPut(name string, body map[string]any) error {\n\tswitch name {',
        'func componentSettingsPut(name string, body map[string]any) error {\n\tif name == "olcrtc" {\n\t\treturn olcrtcSettingsPut(body)\n\t}\n\tswitch name {',
        1,
    )
elif 'func componentSettingsPut' not in t and 'func olcrtcSettingsPut' in t:
    print("[patch-olcrtc-settings] WARN: componentSettingsPut not found yet — defer olcrtc PUT hook")

if 'func readPanelEnvMap' not in t:
    t = t.replace('func componentSettingsGet(name string)', helpers + 'func componentSettingsGet(name string)', 1)

# enrich olcrtcSettingsGet with pins - patch after insert
og_parts = t.split('func olcrtcSettingsGet')
if len(og_parts) > 1 and 'olcrtc_pinned_sha' in t and 'pins := readPins' not in og_parts[1][:400]:
    pass

p.write_text(t)
print("[patch-olcrtc-settings] ok")
PY
