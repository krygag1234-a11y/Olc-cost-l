#!/usr/bin/env bash
# Ensure bridgePoolStatusFile const exists (fix partial apply).
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'bridgePoolStatusFile = "/var/lib/olcrtc/bridge-pool-status.json"' "$MAIN_GO" && {
  echo "[patch-bridge-pool-job-v2] already applied"
  exit 0
}

python3 - "$MAIN_GO" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()
needle = 'bridgeCronPath     = "/etc/cron.d/olcrtc-bridge-pool"'
repl = needle + '\n\tbridgePoolStatusFile = "/var/lib/olcrtc/bridge-pool-status.json"'
if needle in t:
    t = t.replace(needle, repl, 1)
    p.write_text(t)
    print("[patch-bridge-pool-job-v2] ok")
else:
    print("[patch-bridge-pool-job-v2] anchor missing (skip)")
    sys.exit(0)
PY
