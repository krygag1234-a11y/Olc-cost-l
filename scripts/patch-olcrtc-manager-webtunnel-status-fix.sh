#!/usr/bin/env bash
# Fix: don't show webtunnel as "missing" when bridges are disabled.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-webtunnel-status-fix' "$MAIN_GO" && { echo "[patch-webtunnel-status-fix] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Add marker
if 'olc-webtunnel-status-fix' not in t:
    t = t.replace('func featureLiveStatus()', '// olc-webtunnel-status-fix\nfunc featureLiveStatus()', 1)

# Replace webtunnel check: only show if bridges enabled
old_webtunnel = '''\tout["webtunnel"] = "missing"
\tfor _, c := range []string{"/usr/bin/webtunnel-client", "/usr/local/bin/webtunnel-client"} {
\t\tif info, err := os.Stat(c); err == nil && !info.IsDir() {
\t\t\tout["webtunnel"] = filepath.Base(c) + " present"
\t\t\tbreak
\t\t}
\t}'''

new_webtunnel = '''\t// Only check webtunnel if bridges are enabled
\tflags := readFeatureFlags()
\tif flags["bridges"] || flags["tor"] {
\t\tout["webtunnel"] = "missing"
\t\tfor _, c := range []string{"/usr/bin/webtunnel-client", "/usr/local/bin/webtunnel-client"} {
\t\t\tif info, err := os.Stat(c); err == nil && !info.IsDir() {
\t\t\t\tout["webtunnel"] = filepath.Base(c) + " present"
\t\t\t\tbreak
\t\t\t}
\t\t}
\t} else {
\t\tout["webtunnel"] = "disabled (bridges off)"
\t}'''

if old_webtunnel in t:
    t = t.replace(old_webtunnel, new_webtunnel, 1)

p.write_text(t)
print("[patch-webtunnel-status-fix] ok")
PY
