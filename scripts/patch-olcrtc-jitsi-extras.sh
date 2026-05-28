#!/usr/bin/env bash
# Jitsi engine extras: Insecure TLS for TURN (self-signed), longer bridge timeouts for SCTP.
set -euo pipefail
JITSI_GO="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/engine/jitsi/jitsi.go}"
[[ -f "$JITSI_GO" ]] || exit 0

python3 - "$JITSI_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "func jitsiJoinInsecureTLS()" in t:
    print("[patch-jitsi-extras] already applied"); raise SystemExit(0)
    print(0); raise SystemExit(0)

# os import for getenv
if '"os"' not in t.split("import (")[1].split(")")[0]:
    t = t.replace('"fmt"\n', '"fmt"\n\t"os"\n', 1)

helper = """
// jitsiJoinInsecureTLS enables j.Insecure for XMPP and ICE/TURN when the Jitsi
// instance uses self-signed certs (common on RU VPS). Set OLCRTC_JITSI_INSECURE_TLS=1
// in panel.env or the manager unit environment.
func jitsiJoinInsecureTLS() bool {
\tv := strings.TrimSpace(os.Getenv("OLCRTC_JITSI_INSECURE_TLS"))
\treturn v == "1" || strings.EqualFold(v, "true")
}
"""

anchor = "func (s *Session) joinAndOpenBridge(ctx context.Context)"
idx = t.find(anchor)
if idx < 0:
    print("[patch-jitsi-extras] joinAndOpenBridge not found"); raise SystemExit(0)
t = t[:idx] + helper + "\n" + t[idx:]

# SCTP / slow JVB: 30s is too short for conf.hyperia.space and congested bridges
t = t.replace("bridgeOpenTimeout    = 30 * time.Second", "bridgeOpenTimeout    = 60 * time.Second", 1)

p.write_text(t)
print("[patch-jitsi-extras] ok"); raise SystemExit(0)
PY
