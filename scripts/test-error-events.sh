#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/scripts/olc-error-scan.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

printf '{"entries":[]}
' >"$tmpdir/catalog.json"
cat >"$tmpdir/valid.json" <<'JSON'
{
  "clients": [
    {
      "client-id": "demo",
      "locations": [
        {"name": "jitsi-ok", "carrier": "jitsi", "endpoint": {"room_id": "https://meet.example.org/room"}},
        {"name": "telemost-ok", "carrier": "telemost", "endpoint": {"room_id": "123456789"}},
        {"name": "wb-ok", "carrier": "wbstream", "endpoint": {"room_id": "room-token"}}
      ]
    }
  ]
}
JSON

run_scan() {
  OLC_ERROR_CATALOG="$tmpdir/catalog.json" \
  OLCRTC_CONFIG="$1" \
  OLC_NOTIFICATIONS_PATH="$tmpdir/events.json" \
  OLC_NOTIFICATIONS_STATE_PATH="$tmpdir/state.json" \
  "$SCAN"
}

run_scan "$tmpdir/valid.json"
jq -e '[.[] | select((.catalog_id // "") | startswith("config-room-"))] | length == 0' "$tmpdir/events.json" >/dev/null

jq '(.clients[0].locations[0].endpoint.room_id) = ""' "$tmpdir/valid.json" >"$tmpdir/invalid.json"
run_scan "$tmpdir/invalid.json"
jq -e '
  [.[] | select(.active == true and ((.catalog_id // "") | startswith("config-room-")))] as $issues
  | ($issues | length) == 1
  and $issues[0].catalog_id == "config-room-demo-jitsi-ok"
  and ($issues[0].meaning | contains("room_id=''"))
' "$tmpdir/events.json" >/dev/null

run_scan "$tmpdir/valid.json"
jq -e '[.[] | select(.status == "resolved" and ((.catalog_id // "") | startswith("config-room-")))] | length == 1' "$tmpdir/events.json" >/dev/null
jq -e '[.[] | select(.active == true and ((.catalog_id // "") | startswith("config-room-")))] | length == 0' "$tmpdir/events.json" >/dev/null
jq -e '.schema == 2' "$tmpdir/state.json" >/dev/null

echo "test-error-events: PASS"
