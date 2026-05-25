#!/usr/bin/env bash
# Retry j.Join on transient Prosody bind errors (meet.cryptopro.ru "Error loading roster").
set -euo pipefail
JITSI_GO="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/engine/jitsi/jitsi.go}"
[[ -f "$JITSI_GO" ]] || exit 0

python3 - "$JITSI_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
if "joinAndOpenBridgeWithRetry" in t:
    print("[patch-jitsi-retry] already applied")
    raise SystemExit(0)

old = """\tjSess, err := j.Join(ctx, j.Config{
\t\tHost:  s.host,
\t\tRoom:  s.room,
\t\tNick:  s.name,
\t\tDebug: logger.IsVerbose(),
\t})
\tif err != nil {
\t\treturn nil, fmt.Errorf("jitsi join: %w", err)
\t}"""

new = """\tvar jSess *j.Session
\tvar err error
\tfor attempt := 1; attempt <= 4; attempt++ {
\t\tjSess, err = j.Join(ctx, j.Config{
\t\t\tHost:  s.host,
\t\t\tRoom:  s.room,
\t\t\tNick:  s.name,
\t\t\tDebug: logger.IsVerbose(),
\t\t})
\t\tif err == nil {
\t\t\tbreak
\t\t}
\t\tmsg := err.Error()
\t\tif attempt >= 4 || (!strings.Contains(msg, "bind") && !strings.Contains(msg, "xmpp dial")) {
\t\t\treturn nil, fmt.Errorf("jitsi join: %w", err)
\t\t}
\t\tlogger.Warnf("jitsi: join attempt %d failed (%v), retrying in %s", attempt, err, time.Duration(attempt)*2*time.Second)
\t\tselect {
\t\tcase <-ctx.Done():
\t\t\treturn nil, ctx.Err()
\t\tcase <-time.After(time.Duration(attempt) * 2 * time.Second):
\t\t}
\t}
\tif err != nil {
\t\treturn nil, fmt.Errorf("jitsi join: %w", err)
\t}"""

if old not in t:
    raise SystemExit("j.Join block not found")
t = t.replace(old, new, 1)
if '"time"' not in t.split("import (")[1].split(")")[0]:
    t = t.replace('"sync"\n', '"sync"\n\t"time"\n', 1)
p.write_text(t)
print("[patch-jitsi-retry] ok")
PY
