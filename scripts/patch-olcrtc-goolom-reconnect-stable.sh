#!/usr/bin/env bash
# Softer goolom reconnect for Telemost/WB ICE flaps (min interval + longer backoff).
set -euo pipefail
GOOLOM_DIR="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/engine/goolom}"
[[ -d "$GOOLOM_DIR" ]] || exit 1

python3 - "$GOOLOM_DIR" <<'PY'
import sys
from pathlib import Path

dirp = Path(sys.argv[1])
session_go = dirp / "session.go"
lifecycle_go = dirp / "lifecycle.go"

s = session_go.read_text()
if "lastQueueReconnect" not in s:
    s = s.replace(
        "\tlastReconnect  time.Time\n",
        "\tlastReconnect      time.Time\n\tlastQueueReconnect time.Time\n",
        1,
    )
    session_go.write_text(s)

l = lifecycle_go.read_text()

old_q = """func (s *Session) queueReconnect() {
\tif s.closed.Load() || s.reconnecting.Load() {
\t\treturn
\t}
\tif s.shouldReconnect != nil && !s.shouldReconnect() {
\t\treturn
\t}
\tselect {
\tcase s.reconnectCh <- struct{}{}:
\tdefault:
\t}
}"""

new_q = """func (s *Session) queueReconnect() {
\tif s.closed.Load() || s.reconnecting.Load() {
\t\treturn
\t}
\tif s.shouldReconnect != nil && !s.shouldReconnect() {
\t\treturn
\t}
\t// Telemost/WB: ignore rapid reconnect storms (WS ping / brief ICE flap).
\tif !s.lastQueueReconnect.IsZero() && time.Since(s.lastQueueReconnect) < 12*time.Second {
\t\treturn
\t}
\ts.lastQueueReconnect = time.Now()
\tselect {
\tcase s.reconnectCh <- struct{}{}:
\tdefault:
\t}
}"""

if old_q in l:
    l = l.replace(old_q, new_q, 1)

l = l.replace(
    "backoff := time.Duration(s.reconnectCount) * 2 * time.Second",
    "backoff := time.Duration(s.reconnectCount) * 5 * time.Second",
    1,
)
l = l.replace(
    "const maxReconnects = 10",
    "const maxReconnects = 20",
    1,
)

lifecycle_go.write_text(l)
print("[patch-goolom-reconnect-stable] ok")
PY
