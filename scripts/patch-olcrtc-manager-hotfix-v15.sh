#!/usr/bin/env bash
# Hotfix v15: olcrtc/warp feature logs; reclaim stale running component jobs.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v15' "$MAIN_GO" && { echo "[patch-manager-hotfix-v15] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if 'var featureNames = []string{"zapret", "tor", "split", "webtunnel", "warp"}' in t:
    t = t.replace(
        'var featureNames = []string{"zapret", "tor", "split", "webtunnel", "warp"}',
        'var featureNames = []string{"zapret", "tor", "split", "webtunnel", "warp", "olcrtc"}',
        1,
    )
elif '"olcrtc"' not in t.split("var featureNames")[1].split("]")[0]:
    t = re.sub(
        r'var featureNames = \[\]string\{([^}]+)\}',
        lambda m: m.group(0) if '"olcrtc"' in m.group(0) else m.group(0)[:-1] + ', "olcrtc"}',
        t,
        count=1,
    )

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
			"/var/log/olcrtc-component-olcrtc-install.log",
		}
	default:
		return nil
	}
}'''

pat = r"func featureLogPaths\(name string\) \[\]string \{[\s\S]*?\n\}\n"
if re.search(pat, t):
    t = re.sub(pat, new_flp + "\n", t, count=1)
elif "func featureLogPaths" not in t:
    t = t.replace("func tailFileLines", new_flp + "\n\nfunc tailFileLines", 1)

running_stale = r'''
func componentJobRunningStale(st map[string]any, mod time.Time) bool {
	status, _ := st["status"].(string)
	if status != "running" {
		return false
	}
	if raw, ok := st["started_at"].(string); ok && raw != "" {
		if ts, err := time.Parse(time.RFC3339, raw); err == nil {
			return time.Since(ts) > 20*time.Minute
		}
	}
	return time.Since(mod) > 20*time.Minute
}

'''

if "func componentJobRunningStale" not in t:
    t = t.replace("func componentJobStale(st map[string]any", running_stale + "func componentJobStale(st map[string]any", 1)

inject = '''		if status, _ := st["status"].(string); status == "running" && componentJobRunningStale(st, info.ModTime()) {
			st["status"] = "failed"
			st["error"] = "timeout (job stuck — see component log)"
			if st["finished_at"] == nil {
				st["finished_at"] = time.Now().Format(time.RFC3339)
			}
		}
'''
if "componentJobRunningStale(st, info.ModTime())" not in t:
    t = t.replace(
        "\t\tif componentJobStale(st, info.ModTime()) {",
        inject + "\t\tif componentJobStale(st, info.ModTime()) {",
        1,
    )

# Skip empty log files (olcrtc healthcheck 0-byte trap).
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
if old_tail in t and "st.Size() == 0" not in t:
    t = t.replace(old_tail, new_tail, 1)

if "olc-manager-hotfix-v15" not in t:
    if "/* olc-manager-hotfix-v14 */" in t:
        t = t.replace("/* olc-manager-hotfix-v14 */", "/* olc-manager-hotfix-v14 */\n/* olc-manager-hotfix-v15 */", 1)
    else:
        t = "/* olc-manager-hotfix-v15 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v15] ok")
PY
