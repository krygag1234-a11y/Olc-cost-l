#!/usr/bin/env bash
# vp8/sei bindingToken = hash(room.id). Olcbox passes bare room id; do NOT prefix telemost URL in server yaml.
set -euo pipefail
MAIN="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "Room:   olcrtcRoomConfig{ID: loc.Endpoint.RoomID}," in t:
    print("[patch-room-binding] already bare room id"); raise SystemExit(0)
    print(0); raise SystemExit(0)

if "bindingRoomURL(loc.Carrier" not in t:
    print("[patch-room-binding] skip: bindingRoomURL not in serverConfig"); raise SystemExit(0)
    print(0); raise SystemExit(0)

t = t.replace(
    "Room:   olcrtcRoomConfig{ID: bindingRoomURL(loc.Carrier, loc.Endpoint.RoomID)},",
    "Room:   olcrtcRoomConfig{ID: loc.Endpoint.RoomID},",
    1,
)

note = """
// NOTE: room.id in yaml/subscription must match Olcbox (bare telemost id, not https:// URL).
// Telemost auth expands bare id for API; vp8/sei bindingToken hashes the same bare value.
"""
if "NOTE: room.id in yaml/subscription must match Olcbox" not in t:
    t = t.replace("func serverConfig(loc Location)", note + "func serverConfig(loc Location)", 1)

p.write_text(t)
print("[patch-room-binding] ok (reverted telemost URL prefix in server yaml)"); raise SystemExit(0)
PY
