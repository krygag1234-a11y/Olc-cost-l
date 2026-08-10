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
feature_script="$SCRIPT_DIR/olc-feature.sh"
webtunnel_block="$(sed -n '/^webtunnel_on()/,/^}/p' "$feature_script")"
build_line="$(grep -n 'if build_webtunnel_client' <<<"$webtunnel_block" | cut -d: -f1)"
save_line="$(grep -n '_save OLCRTC_ENABLE_WEBTUNNEL 1' <<<"$webtunnel_block" | cut -d: -f1)"
[[ -n "$build_line" && -n "$save_line" ]]
(( save_line > build_line ))

installer="$SCRIPT_DIR/install-tor-pluggable-transports.sh"
[[ "$(bash "$installer" --plan --types obfs4)" == "[transport-plan] obfs4=1 webtunnel=0 snowflake=0" ]]
[[ "$(bash "$installer" --plan --types webtunnel,snowflake)" == "[transport-plan] obfs4=0 webtunnel=1 snowflake=1" ]]
[[ "$(bash "$installer" --plan --types obfs4,webtunnel,snowflake)" == "[transport-plan] obfs4=1 webtunnel=1 snowflake=1" ]]
manager="$SCRIPT_DIR/../components/olcrtc-manager/cmd/olcrtc-manager/main.go"
grep -qF 'exec.Command("bash", installer, "--types", types)' "$manager"
grep -qF '"stage": "install-transports"' "$manager"
grep -qF 'types = "obfs4"' "$manager"
! grep -qF 'types = "obfs4,webtunnel"' "$manager"

echo 'bridge-profile-types: PASS'
