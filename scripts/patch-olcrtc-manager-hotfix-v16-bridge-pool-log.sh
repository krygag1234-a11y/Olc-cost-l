#!/usr/bin/env bash
# Hotfix v16: live bridge-pool log tail while job running (for settings UI).
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v16-bridge-pool' "$MAIN_GO" && { echo "[patch-manager-hotfix-v16-bridge-pool] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old = '''func readBridgePoolStatus() map[string]any {
\tvar st map[string]any
\tif readJSONFile(bridgePoolStatusFile, &st) {
\t\tst["webtunnel_client"] = fileExists("/usr/bin/webtunnel-client") || fileExists("/usr/local/bin/webtunnel-client")
\t\treturn st
\t}
\treturn map[string]any{"status": "idle", "webtunnel_client": fileExists("/usr/bin/webtunnel-client")}
}'''

new = '''func readBridgePoolStatus() map[string]any {
\tvar st map[string]any
\tif readJSONFile(bridgePoolStatusFile, &st) {
\t\tst["webtunnel_client"] = fileExists("/usr/bin/webtunnel-client") || fileExists("/usr/local/bin/webtunnel-client")
\t\tstatus, _ := st["status"].(string)
\t\tlogPath, _ := st["log_path"].(string)
\t\tif logPath == "" {
\t\t\tlogPath = "/var/log/olcrtc-bridge-pool.log"
\t\t}
\t\tif status == "running" || status == "done" || status == "error" {
\t\t\tif tail := tailLogFile(logPath, 120); len(tail) > 0 {
\t\t\t\tst["log_tail"] = tail
\t\t\t}
\t\t}
\t\treturn st
\t}
\treturn map[string]any{"status": "idle", "webtunnel_client": fileExists("/usr/bin/webtunnel-client")}
}'''

if old in t:
    t = t.replace(old, new, 1)
else:
    print("[patch-manager-hotfix-v16-bridge-pool] readBridgePoolStatus anchor missing", file=sys.stderr)
    sys.exit(1)

if "olc-manager-hotfix-v16-bridge-pool" not in t:
    if "/* olc-manager-hotfix-v15 */" in t:
        t = t.replace("/* olc-manager-hotfix-v15 */", "/* olc-manager-hotfix-v15 */\n/* olc-manager-hotfix-v16-bridge-pool */", 1)
    else:
        t = "/* olc-manager-hotfix-v16-bridge-pool */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v16-bridge-pool] ok")
PY
