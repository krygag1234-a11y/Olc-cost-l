#!/usr/bin/env bash
# Hotfix v13: log webtunnel install during bridge pool refresh.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v13' "$MAIN_GO" && { echo "[patch-manager-hotfix-v13] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old = '''		if strings.Contains(strings.ToLower(types), "webtunnel") {
			wt := filepath.Join(repo, "scripts/install-tor-pluggable-transports.sh")
			if _, err := os.Stat(wt); err == nil {
				_ = exec.Command("bash", wt).Run()
			}
		}'''

new = '''		if strings.Contains(strings.ToLower(types), "webtunnel") {
			wt := filepath.Join(repo, "scripts/install-tor-pluggable-transports.sh")
			if _, err := os.Stat(wt); err == nil {
				appendBridgePoolLog("[bridge-pool] installing webtunnel-client (mirror-cry first)...")
				wtCmd := exec.Command("bash", wt)
				wtCmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
				out, wtErr := wtCmd.CombinedOutput()
				if len(out) > 0 {
					appendBridgePoolLog(string(out))
				}
				if wtErr != nil {
					appendBridgePoolLog("[bridge-pool] webtunnel install error: " + wtErr.Error())
				}
			}
		}'''

if old in t:
    t = t.replace(old, new, 1)

if "func appendBridgePoolLog(" not in t:
    fn = '''
func appendBridgePoolLog(line string) {
	line = strings.TrimSpace(line)
	if line == "" {
		return
	}
	f, err := os.OpenFile("/var/log/olcrtc-bridge-pool.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	if !strings.HasSuffix(line, "\\n") {
		line += "\\n"
	}
	_, _ = f.WriteString(line)
}

'''
    t = t.replace("func writeBridgePoolStatus(st map[string]any) {", fn + "func writeBridgePoolStatus(st map[string]any) {", 1)

if "/* olc-manager-hotfix-v12 */" in t:
    t = t.replace("/* olc-manager-hotfix-v12 */", "/* olc-manager-hotfix-v12 */\n/* olc-manager-hotfix-v13 */", 1)
else:
    t = "/* olc-manager-hotfix-v13 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v13] ok")
PY
