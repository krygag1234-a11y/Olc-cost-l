#!/usr/bin/env bash
# List/disable duplicate Jitsi panel clients pointing at the same meet host+room.
# Run on VPS: sudo bash /opt/Olc-cost-l/scripts/prune-duplicate-jitsi-clients.sh [--dry-run]
set -euo pipefail

CONFIG="${OLCRTC_MANAGER_CONFIG:-/etc/olcrtc-manager/config.json}"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

[[ -f "$CONFIG" ]] || { echo "missing $CONFIG"; exit 1; }

python3 - "$CONFIG" "$DRY" <<'PY'
import json, sys
from collections import defaultdict

path, dry = sys.argv[1], int(sys.argv[2])
with open(path) as f:
    cfg = json.load(f)

clients = cfg.get("clients") or []
by_room = defaultdict(list)
for i, c in enumerate(clients):
    for j, loc in enumerate(c.get("locations") or []):
        if (loc.get("carrier") or "").lower() != "jitsi":
            continue
        ep = loc.get("endpoint") or {}
        room = (ep.get("room_id") or ep.get("roomId") or "").strip()
        if room:
            by_room[room.lower()].append((i, j, c.get("id", "?"), room))

dups = {k: v for k, v in by_room.items() if len(v) > 1}
if not dups:
    print("No duplicate Jitsi room bindings.")
    sys.exit(0)

print("Duplicate Jitsi rooms (keep first client per room, disable rest in panel):")
for room, entries in dups.items():
    print(f"\n  {room}")
    for k, (ci, lj, cid, _) in enumerate(entries):
        mark = "KEEP" if k == 0 else "DISABLE"
        print(f"    [{mark}] client={cid} locations[{lj}]")

if dry:
    print("\n(dry-run — disable extra clients manually in /admin)")
else:
    print("\nDisable extra clients in panel UI; then: systemctl restart olcrtc-manager")
PY
