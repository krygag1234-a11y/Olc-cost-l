#!/usr/bin/env bash
# After-save hooks: zapret reload, split refresh, tor exit nodes.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'componentSettingsAfterSave' "$MAIN_GO" && { echo "[patch-settings-actions] already applied"; exit 0; }

python3 - "$MAIN_GO" "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
repo = Path(sys.argv[2])
t = p.read_text()

if 'componentSettingsAfterSave' not in t:
    hook = r'''
func componentSettingsAfterSave(name string, body map[string]any) {
	repo := olcRepoRoot()
	switch name {
	case "zapret":
		script := filepath.Join(repo, "scripts/zapret-sync-excludes.sh")
		if _, err := os.Stat(script); err == nil {
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
				defer cancel()
				cmd := exec.CommandContext(ctx, "bash", script, "--reload-zapret")
				cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
				_, _ = cmd.CombinedOutput()
			}()
		}
	case "split":
		if v, ok := body["refresh_lists"].(bool); ok && v {
			script := filepath.Join(repo, "scripts/setup-split-ru.sh")
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
				defer cancel()
				cmd := exec.CommandContext(ctx, "bash", script)
				cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
				_, _ = cmd.CombinedOutput()
			}()
		}
	case "tor":
		if v, ok := body["exit_nodes"].(string); ok {
			_ = writeTextFile("/etc/olcrtc-manager/tor-exit.env", "OLCRTC_TOR_EXIT_NODES="+strings.TrimSpace(v)+"\n")
			script := filepath.Join(repo, "scripts/configure-tor-exit.sh")
			if _, err := os.Stat(script); err == nil {
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
					defer cancel()
					cmd := exec.CommandContext(ctx, "bash", "-c", "set -a; source /etc/olcrtc-manager/tor-exit.env 2>/dev/null; set +a; bash "+script)
					cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
					_, _ = cmd.CombinedOutput()
				}()
			}
		}
	}
}

'''
    t = t.replace('func componentSettingsHandler()', hook + 'func componentSettingsHandler()', 1)

old = '\t\t\twriteJSON(w, map[string]string{"status": "ok"})'
new = '\t\t\tcomponentSettingsAfterSave(name, body)\n\t\t\twriteJSON(w, map[string]string{"status": "ok"})'
if old in t and 'componentSettingsAfterSave(name, body)' not in t:
    t = t.replace(old, new, 1)

if 'body["exit_nodes"]' not in t:
    t = t.replace(
        '\tcase "tor":\n\t\t// Tor port / exit nodes — warn only in UI; full torrc edit needs olc-update\n\t\treturn nil',
        '\tcase "tor":\n\t\tif v, ok := body["exit_nodes"].(string); ok {\n\t\t\t_ = writeTextFile("/etc/olcrtc-manager/tor-exit.env", "OLCRTC_TOR_EXIT_NODES="+strings.TrimSpace(v)+"\\n")\n\t\t}\n\t\treturn nil',
        1,
    )

p.write_text(t)
print("[patch-settings-actions] ok")
PY
