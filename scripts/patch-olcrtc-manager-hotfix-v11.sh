#!/usr/bin/env bash
# Hotfix v11: per-feature log paths (warp / olcrtc / components) + clearer missing-log message.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

new_flp = r'''func featureLogPaths(name string) []string {
	switch name {
	case "zapret":
		return []string{
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-component-zapret-install.log",
			"/var/log/olcrtc-component-zapret-uninstall.log",
		}
	case "tor":
		return []string{"/var/log/olcrtc-healthcheck.log", "/var/log/tor/log"}
	case "split":
		return []string{
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-healthcheck.log",
			"/var/log/olcrtc-component-split-install.log",
			"/var/log/olcrtc-component-split-uninstall.log",
		}
	case "webtunnel":
		return []string{
			"/var/log/olcrtc-bridge-pool.log",
			"/var/log/olcrtc-bridge-monitor.log",
			"/var/log/olcrtc-component-bridges-install.log",
			"/var/log/olcrtc-component-bridges-uninstall.log",
		}
	case "warp":
		return []string{
			"/var/log/olcrtc-warp-install.log",
			"/var/log/olcrtc-component-warp-install.log",
			"/var/log/olcrtc-component-warp-uninstall.log",
		}
	case "olcrtc":
		return []string{
			"/var/log/olcrtc-feature-restart.log",
			"/var/log/olcrtc-panel-update.log",
			"/var/log/olcrtc-healthcheck.log",
		}
	default:
		return nil
	}
}'''

pat = r"func featureLogPaths\(name string\) \[\]string \{[\s\S]*?\n\}\n\nfunc tailFileLines"
m = re.search(pat, t)
if not m:
    print("[patch-manager-hotfix-v11] featureLogPaths block not found", file=sys.stderr)
    sys.exit(1)
t = t[: m.start()] + new_flp + "\n\nfunc tailFileLines" + t[m.end() :]

old_err = '\t\tif lines == nil {\n\t\t\tlines = []string{"(log file not found — run olc-update or check /var/log/olcrtc-*)"}\n\t\t}'
new_err = '''\t\tif lines == nil {
\t\t\tpaths := featureLogPaths(name)
\t\t\tmsg := fmt.Sprintf("(log file not found for %s — tried: %s)", name, strings.Join(paths, ", "))
\t\t\tif len(paths) == 0 {
\t\t\t\tmsg = fmt.Sprintf("(no log paths configured for %s)", name)
\t\t\t}
\t\t\tlines = []string{msg}
\t\t}'''
if old_err in t:
    t = t.replace(old_err, new_err, 1)

if 'if !allowed && name == "olcrtc"' not in t:
    t = t.replace(
        '\t\tif !allowed {\n\t\t\thttp.Error(w, "unknown feature", http.StatusBadRequest)\n\t\t\treturn\n\t\t}\n\t\tvar usedPath string\n',
        '\t\tif !allowed && (name == "olcrtc" || name == "warp") {\n\t\t\tallowed = true\n\t\t}\n\t\tif !allowed {\n\t\t\thttp.Error(w, "unknown feature", http.StatusBadRequest)\n\t\t\treturn\n\t\t}\n\t\tvar usedPath string\n',
        1,
    )

if "olc-manager-hotfix-v11" not in t:
    if "/* olc-manager-hotfix-v10 */" in t:
        t = t.replace("/* olc-manager-hotfix-v10 */", "/* olc-manager-hotfix-v10 */\n/* olc-manager-hotfix-v11 */", 1)
    else:
        t = "/* olc-manager-hotfix-v11 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v11] ok")
PY
