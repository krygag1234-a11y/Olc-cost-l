#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/etc" "$TMP/lists/disabled" "$TMP/removed" "$TMP/profiles" "$TMP/zapret/nfq"
for x in tor obfs4proxy; do printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/bin/$x"; chmod +x "$TMP/bin/$x"; done
cat >"$TMP/bin/dpkg-query" <<'SH'
#!/usr/bin/env bash
printf 'install ok installed'
SH
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/zapret/nfq/nfqws"
chmod +x "$TMP/bin/dpkg-query" "$TMP/zapret/nfq/nfqws"
printf 'preserved split config\n' >"$TMP/lists/disabled/ru-direct-domains.txt"
printf 'Bridge obfs4 example.invalid:1 FINGERPRINT cert=x iat-mode=0\n' >"$TMP/bridges.conf"
cat >"$TMP/profile.json" <<'JSON'
{"schema":1,"profile_id":"ru-full","components":{"tor":false,"split":false,"zapret":true,"bridges":false,"warp":false},"panel":{"access":"ip","tls":false},"ru_vps":true}
JSON
cat >"$TMP/features.env" <<'ENV'
OLCRTC_ENABLE_ZAPRET=0
OLCRTC_ENABLE_TOR=0
OLCRTC_ENABLE_SPLIT=0
OLCRTC_ENABLE_BRIDGES=0
OLCRTC_ENABLE_WEBTUNNEL=0
OLCRTC_ENABLE_WARP=0
ENV
before_features="$(sha256sum "$TMP/features.env" | awk '{print $1}')"
export PATH="$TMP/bin:/usr/bin:/bin"
export OLCRTC_DEPLOY_PROFILE="$TMP/profile.json"
export OLCRTC_PROFILES_DIR="$TMP/profiles"
export OLCRTC_FEATURES_ENV="$TMP/features.env"
export OLCRTC_COMPONENT_REMOVED_DIR="$TMP/removed"
export OLCRTC_SPLIT_LISTS_DIR="$TMP/lists"
export OLCRTC_TOR_BRIDGES_CONF="$TMP/bridges.conf"
export OLCRTC_ZAPRET_BIN="$TMP/zapret/nfq/nfqws"
export OLC_PROFILE_LOG_QUIET=1
# shellcheck source=lib-deploy-profile.sh
source "$SCRIPT_DIR/lib-deploy-profile.sh"
profile_apply_env
jq -e '.schema == 2 and .components.tor == true and .components.split == true and .components.zapret == true and .components.bridges == true and .components.warp == false' "$TMP/profile.json" >/dev/null
jq -e '.legacy_schema1_components.tor == false and .legacy_schema1_components.zapret == true' "$TMP/profile.json" >/dev/null
[[ "$ENABLE_TOR:$ENABLE_SPLIT:$ENABLE_ZAPRET:$ENABLE_BRIDGES:$ENABLE_WARP" == "1:1:1:1:0" ]]
[[ "$OLCRTC_ENABLE_TOR:$OLCRTC_ENABLE_SPLIT:$OLCRTC_ENABLE_ZAPRET:$OLCRTC_ENABLE_BRIDGES:$OLCRTC_ENABLE_WARP" == "0:0:0:0:0" ]]
[[ "$(sha256sum "$TMP/features.env" | awk '{print $1}')" == "$before_features" ]]
mapfile -t backups < <(find "$TMP" -maxdepth 1 -name 'profile.json.bak-schema1-*' -print)
[[ "${#backups[@]}" -eq 1 ]]
profile_apply_env
mapfile -t backups_after < <(find "$TMP" -maxdepth 1 -name 'profile.json.bak-schema1-*' -print)
[[ "${#backups_after[@]}" -eq 1 ]]
[[ "$(sha256sum "$TMP/features.env" | awk '{print $1}')" == "$before_features" ]]

# Runtime dependency cascades must not erase independently installed modules.
profile_after_component_job tor uninstall
jq -e '.components.tor == false and .components.split == true and .components.bridges == true' "$TMP/profile.json" >/dev/null
profile_after_component_job tor install
profile_after_component_job bridges uninstall
jq -e '.components.tor == true and .components.split == true and .components.bridges == false' "$TMP/profile.json" >/dev/null

echo 'component-state-model: PASS'
