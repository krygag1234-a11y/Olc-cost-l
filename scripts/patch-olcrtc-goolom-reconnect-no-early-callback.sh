#!/usr/bin/env bash
# fix/all already removed the early onReconnect(nil) call in lifecycle.go.
# This patch is now a no-op but kept for idempotency with older pins.
set -euo pipefail
LIFECYCLE="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/engine/goolom/lifecycle.go}"
[[ -f "$LIFECYCLE" ]] || exit 1

python3 - "$LIFECYCLE" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
# fix/all already removed the early callback; marker check is for old pins.
if "// PATCH: no early onReconnect" in t:
    print("[patch-goolom-reconnect-no-early-callback] already patched (old pin)")
    raise SystemExit(0)

# On fix/all the block simply no longer exists — nothing to do.
if "s.onReconnect(nil)" not in t:
    print("[patch-goolom-reconnect-no-early-callback] ok (fix/all already removed it)")
    raise SystemExit(0)

old = """\tif s.onReconnect != nil {
\t\ts.onReconnect(nil)
\t}

\ttime.Sleep(3 * time.Second)"""

new = """\t// PATCH: no early onReconnect before goolom reconnect completes
\t// Upper layers used to reinstall smux here; that dropped active tunnels while ICE
\t// was still reconnecting. Notify only after Connect() succeeds below.

\ttime.Sleep(3 * time.Second)"""

if old not in t:
    print("[patch-goolom-reconnect-no-early-callback] skip: block not found")
    raise SystemExit(0)
p.write_text(t.replace(old, new, 1))
print("[patch-goolom-reconnect-no-early-callback] ok")
PY
