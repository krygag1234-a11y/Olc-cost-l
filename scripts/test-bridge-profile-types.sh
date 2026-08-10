#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export BRIDGE_PROFILES_PATH="$TMP/profiles.json"
# shellcheck source=tor-bridge-lib.sh
source "$SCRIPT_DIR/tor-bridge-lib.sh"

cat >"$BRIDGE_PROFILES_PATH" <<'JSON'
{"active_profile":"system","system":{"types":"obfs4,webtunnel"},"profiles":[]}
JSON
[[ "$(get_bridge_types_from_profile)" == "obfs4,webtunnel" ]]

cat >"$BRIDGE_PROFILES_PATH" <<'JSON'
{
  "active_profile":"custom-types",
  "system":{"types":"obfs4"},
  "profiles":[{"id":"custom-types","types":"snowflake,webtunnel"}]
}
JSON
[[ "$(get_bridge_types_from_profile)" == "snowflake,webtunnel" ]]

cat >"$BRIDGE_PROFILES_PATH" <<'JSON'
{
  "active_profile":"manual-lines",
  "system":{"types":"obfs4"},
  "profiles":[{
    "id":"manual-lines",
    "bridges":"Bridge snowflake 192.0.2.3:80\nBridge obfs4 198.51.100.4:443 X cert=Y iat-mode=0\nBridge snowflake 192.0.2.3:80"
  }]
}
JSON
[[ "$(get_bridge_types_from_profile)" == "obfs4,snowflake" ]]

cat >"$BRIDGE_PROFILES_PATH" <<'JSON'
{"active_profile":"legacy","legacy":{"types":"webtunnel"}}
JSON
[[ "$(get_bridge_types_from_profile)" == "webtunnel" ]]
