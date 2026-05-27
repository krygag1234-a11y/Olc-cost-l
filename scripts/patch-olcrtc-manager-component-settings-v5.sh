#!/usr/bin/env bash
# Strategy presets, cidr_only toggle, zapret reinstall hook.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'component-settings-v5' "$MAIN_GO" && { echo "[patch-component-settings-v5] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()
if '// component-settings-v5' not in t:
    t = t.replace('// component-settings-v4\n', '// component-settings-v4\n// component-settings-v5\n', 1)

helpers = r'''
func zapretStrategyState() (current string, presets []map[string]string) {
	current = strings.TrimSpace(readTextFile("/etc/olcrtc-manager/zapret.strategy"))
	if current == "" {
		if fileExists(filepath.Join(olcRepoRoot(), "data/zapret4rocket/config.default")) {
			current = "z4r-default"
		} else {
			current = "olcrtc-minimal"
		}
	}
	presets = []map[string]string{
		{"id": "olcrtc-minimal", "label": "Olc minimal (лёгкий)"},
		{"id": "z4r-default", "label": "zapret4rocket config.default"},
	}
	dir := filepath.Join(olcRepoRoot(), "data/zapret-strategies")
	if ents, err := os.ReadDir(dir); err == nil {
		for _, e := range ents {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".config") {
				continue
			}
			id := strings.TrimSuffix(e.Name(), ".config")
			presets = append(presets, map[string]string{"id": id, "label": "custom: " + id})
		}
	}
	return current, presets
}

func splitCidrOnlyEnabled() bool {
	env := readPanelEnvMap()
	if v := strings.TrimSpace(env["OLCRTC_SPLIT_CIDR_ONLY"]); v == "1" || strings.EqualFold(v, "true") {
		return true
	}
	cidr := env["OLCRTC_DIRECT_CIDRS"]
	return strings.Contains(cidr, "ru-cidrs") && !strings.Contains(cidr, "direct-all")
}
'''

if 'func zapretStrategyState' not in t:
    t = t.replace('func componentSettingsHandler()', helpers + '\nfunc componentSettingsHandler()', 1)

# Extend zapret GET return — add strategy_presets after strategy field
if '"strategy_presets"' not in t:
    t = t.replace(
        '"strategy":        strategy,',
        '''"strategy":         strategy,
			"strategy_presets": func() []map[string]string { _, p := zapretStrategyState(); return p }(),
			"strategy_current": func() string { c, _ := zapretStrategyState(); return c }(),''',
        1,
    )

# split GET cidr_only fix
t = t.replace(
    '"cidr_only":             strings.Contains(env["OLCRTC_DIRECT_CIDRS"], "ru-cidrs"),',
    '"cidr_only":             splitCidrOnlyEnabled(),',
    1,
)

# zapret PUT strategy
if 'body["strategy_id"]' not in t:
    t = t.replace(
        '''		if v, ok := body["nfqws_config"].(string); ok {
			cfgPath := filepath.Join(olcRepoRoot(), "data/zapret-olcrtc.config")
			if err := writeTextFile(cfgPath, strings.TrimSpace(v)+"\\n"); err != nil {
				return err
			}
		}
		if v, ok := body["auto_sync"].(bool); ok {''',
        '''		if v, ok := body["nfqws_config"].(string); ok {
			cfgPath := filepath.Join(olcRepoRoot(), "data/zapret-olcrtc.config")
			if err := writeTextFile(cfgPath, strings.TrimSpace(v)+"\\n"); err != nil {
				return err
			}
		}
		if v, ok := body["strategy_id"].(string); ok && strings.TrimSpace(v) != "" {
			script := filepath.Join(olcRepoRoot(), "scripts/olc-zapret-apply-strategy.sh")
			if _, err := os.Stat(script); err == nil {
				go func(id string) {
					ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
					defer cancel()
					cmd := exec.CommandContext(ctx, "bash", script, strings.TrimSpace(id))
					cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
					_, _ = cmd.CombinedOutput()
				}(v)
			}
		}
		if v, ok := body["reinstall"].(bool); ok && v {
			script := filepath.Join(olcRepoRoot(), "scripts/olc-component-job.sh")
			if _, err := os.Stat(script); err == nil {
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
					defer cancel()
					cmd := exec.CommandContext(ctx, "bash", script, "zapret", "install")
					cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin", "OLCRTC_ZAPRET_REINSTALL=1")
					_, _ = cmd.CombinedOutput()
				}()
			}
		}
		if v, ok := body["auto_sync"].(bool); ok {''',
        1,
    )

# split PUT cidr_only
if 'body["cidr_only"]' not in t.split('case "split":')[1].split('case "bridges"')[0]:
    t = t.replace(
        '''	case "split":
		if v, ok := body["custom_direct_domains"].(string); ok {''',
        '''	case "split":
		if v, ok := body["cidr_only"].(bool); ok {
			val := "0"
			if v {
				val = "1"
			}
			_ = safetyPanelEnvSet("/etc/olcrtc-manager/panel.env", "OLCRTC_SPLIT_CIDR_ONLY", val)
			script := filepath.Join(olcRepoRoot(), "scripts/setup-split-ru.sh")
			include := "0"
			if !v {
				include = "1"
			}
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
				defer cancel()
				cmd := exec.CommandContext(ctx, "bash", script)
				cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin", "OLCRTC_INCLUDE_CDN_IPS="+include)
				_, _ = cmd.CombinedOutput()
			}()
		}
		if v, ok := body["custom_direct_domains"].(string); ok {''',
        1,
    )
    # safetyPanelEnvSet may not exist in Go - use writeTextFile append or panel env helper
    if 'func safetyPanelEnvSet' not in t:
        t = t.replace(
            '_ = safetyPanelEnvSet("/etc/olcrtc-manager/panel.env", "OLCRTC_SPLIT_CIDR_ONLY", val)',
            '_ = patchPanelEnvKey("OLCRTC_SPLIT_CIDR_ONLY", val)',
            1,
        )

if 'func patchPanelEnvKey' not in t:
    patch_env = r'''
func patchPanelEnvKey(key, val string) error {
	path := "/etc/olcrtc-manager/panel.env"
	lines := strings.Split(readTextFile(path), "\n")
	prefix := key + "="
	found := false
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), prefix) {
			lines[i] = prefix + val
			found = true
			break
		}
	}
	if !found {
		lines = append(lines, prefix+val)
	}
	return writeTextFile(path, strings.Join(lines, "\n")+"\n")
}
'''
    t = t.replace('func zapretStrategyState()', patch_env + '\nfunc zapretStrategyState()', 1)

p.write_text(t)
print("[patch-component-settings-v5] ok")
PY
