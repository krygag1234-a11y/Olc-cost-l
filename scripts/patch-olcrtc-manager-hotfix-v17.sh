#!/usr/bin/env bash
# Hotfix v17: force featureLogPaths (warp/olcrtc), fix v12 regex miss on fresh apply.
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
		}
	case "webtunnel":
		return []string{
			"/var/log/olcrtc-bridge-pool.log",
			"/var/log/olcrtc-bridge-monitor.log",
			"/var/log/olcrtc-component-bridges-install.log",
		}
	case "warp":
		return []string{
			"/var/log/olcrtc-warp-install.log",
			"/var/log/olcrtc-component-warp-install.log",
			"/var/log/olcrtc-component-warp-uninstall.log",
			"/var/log/syslog",
		}
	case "olcrtc":
		return []string{
			"/var/log/olcrtc-healthcheck.log",
			"/var/log/olcrtc-panel-update.log",
			"/var/log/olcrtc-feature-restart.log",
		}
	default:
		return nil
	}
}'''

_flp_parts = t.split("func featureLogPaths")
_flp_body = _flp_parts[1].split("func tailFileLines")[0] if len(_flp_parts) > 1 else ""
if "func featureLogPaths" not in t:
    print("[patch-manager-hotfix-v17] featureLogPaths not found (skip)")
elif "case \"olcrtc\":" not in _flp_body:
    t2, n = re.subn(
        r"func featureLogPaths\(name string\) \[\]string \{[\s\S]*?\n\}",
        new_flp,
        t,
        count=1,
    )
    if n:
        t = t2
        print("[patch-manager-hotfix-v17] featureLogPaths replaced")
    else:
        print("[patch-manager-hotfix-v17] featureLogPaths replace failed", file=sys.stderr)
        sys.exit(1)

if 'if !allowed && (name == "olcrtc" || name == "warp")' not in t:
    t = t.replace(
        '\t\tif !allowed {\n\t\t\thttp.Error(w, "unknown feature", http.StatusBadRequest)\n\t\t\treturn\n\t\t}\n\t\tvar usedPath string\n',
        '\t\tif !allowed && (name == "olcrtc" || name == "warp") {\n\t\t\tallowed = true\n\t\t}\n\t\tif !allowed {\n\t\t\thttp.Error(w, "unknown feature", http.StatusBadRequest)\n\t\t\treturn\n\t\t}\n\t\tvar usedPath string\n',
        1,
    )

_flh_parts = t.split("func featuresLogsHandler")
_flh_body = _flh_parts[1].split("func featuresListHandler")[0] if len(_flh_parts) > 1 else ""
if "func featuresLogsHandler" in t and "st.Size() == 0" not in _flh_body:
    old_tail = """\t\tfor _, path := range featureLogPaths(name) {
\t\t\tgot, err := tailFileLines(path, 200)
\t\t\tif err != nil {
\t\t\t\tcontinue
\t\t\t}
\t\t\tusedPath = path
\t\t\tlines = got
\t\t\tbreak
\t\t}"""
    new_tail = """\t\tfor _, path := range featureLogPaths(name) {
\t\t\tif st, err := os.Stat(path); err != nil || st.Size() == 0 {
\t\t\t\tcontinue
\t\t\t}
\t\t\tgot, err := tailFileLines(path, 200)
\t\t\tif err != nil || len(got) == 0 {
\t\t\t\tcontinue
\t\t\t}
\t\t\tusedPath = path
\t\t\tlines = got
\t\t\tbreak
\t\t}"""
    if old_tail in t:
        t = t.replace(old_tail, new_tail, 1)

if "olc-manager-hotfix-v17" not in t:
    t = "/* olc-manager-hotfix-v17 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v17] ok")
PY
