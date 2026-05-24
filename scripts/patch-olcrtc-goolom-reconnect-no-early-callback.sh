#!/usr/bin/env bash
# Do not tear smux/link before goolom reconnect finishes (onReconnect(nil) was too early).
set -euo pipefail
LIFECYCLE="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/engine/goolom/lifecycle.go}"
[[ -f "$LIFECYCLE" ]] || exit 1

python3 - "$LIFECYCLE" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
marker = "// PATCH: no early onReconnect before goolom reconnect completes"
if marker in t:
    print("[patch-goolom-reconnect-no-early-callback] already patched")
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
    raise SystemExit("reconnect() block not found")
p.write_text(t.replace(old, new, 1))
print("[patch-goolom-reconnect-no-early-callback] ok")
PY
