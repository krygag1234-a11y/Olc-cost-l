#!/usr/bin/env bash
# Match Olcbox UI: DataChannel, VP8, SEI only (no videochannel in Olcbox).
set -euo pipefail
PANEL="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
MAIN="${2:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$PANEL" ]] || exit 0

python3 - "$PANEL" "$MAIN" <<'PY'
import re
import sys
from pathlib import Path

panel = Path(sys.argv[1])
main = Path(sys.argv[2]) if len(sys.argv) > 2 else None
t = panel.read_text()

new_block = """const transportsByCarrier: Record<string, string[]> = {
  jitsi: ["datachannel", "vp8channel", "seichannel", "videochannel"],
  wbstream: ["datachannel", "vp8channel", "seichannel"],
  telemost: ["vp8channel", "seichannel"],
  jazz: ["datachannel"],
};"""

if new_block in t:
    print("[patch-panel-transports] already olcbox-aligned")
else:
    t = re.sub(
        r"const transportsByCarrier: Record<string, string\[\]> = \{[\s\S]*?\};",
        new_block,
        t,
        count=1,
    )
    if new_block not in t:
        raise SystemExit("patch-panel-transports: failed to replace block")
panel.write_text(t)

if main and main.exists():
    mt = main.read_text()
    # isSupported matrix aligned with Olcbox + upstream
    wb = """\t\t"wbstream": {
\t\t\t"datachannel":  true,
\t\t\t"vp8channel":   true,
\t\t\t"seichannel":   true,
\t\t\t"videochannel": false,
\t\t},"""
    tm = """\t\t"telemost": {
\t\t\t"datachannel":  false,
\t\t\t"vp8channel":   true,
\t\t\t"seichannel":   true,
\t\t\t"videochannel": false,
\t\t},"""
    mt = re.sub(
        r'\t\t"wbstream": \{[\s\S]*?\},',
        wb,
        mt,
        count=1,
    )
    mt = re.sub(
        r'\t\t"telemost": \{[\s\S]*?\},',
        tm,
        mt,
        count=1,
    )
    main.write_text(mt)

print("[patch-panel-transports] ok (olcbox: DC/VP8/SEI; no video in panel)")
PY
