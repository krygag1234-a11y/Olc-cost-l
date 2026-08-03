#!/usr/bin/env bash
# Install only the transport submodules selected for the Tor Bridges module.
# Usage: install-tor-pluggable-transports.sh [--types obfs4,webtunnel,snowflake] [--plan]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-webtunnel-build.sh
source "$SCRIPT_DIR/lib-webtunnel-build.sh"

types="${BRIDGE_TYPES:-obfs4}"
plan=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --types) types="${2:?missing --types value}"; shift 2 ;;
    --plan) plan=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
types=",${types// /},"
want_type() { [[ "$types" == *",all,"* || "$types" == *",$1,"* ]]; }

want_obfs4=0
want_webtunnel=0
want_snowflake=0
want_type obfs4 && want_obfs4=1
want_type webtunnel && want_webtunnel=1
want_type snowflake && want_snowflake=1

if [[ "$plan" -eq 1 ]]; then
  echo "[transport-plan] obfs4=$want_obfs4 webtunnel=$want_webtunnel snowflake=$want_snowflake"
  exit 0
fi

apt-get update -qq
packages=(apparmor-utils curl)
[[ "$want_obfs4" -eq 1 ]] && packages+=(obfs4proxy)
[[ "$want_snowflake" -eq 1 ]] && packages+=(snowflake-client)
apt-get install -y -qq "${packages[@]}"

if [[ "$want_webtunnel" -eq 1 ]]; then
  build_webtunnel_client echo || true
fi

mkdir -p /etc/apparmor.d/local
for entry in "obfs4proxy:$want_obfs4" "webtunnel-client:$want_webtunnel" "snowflake-client:$want_snowflake"; do
  bin="${entry%%:*}"
  enabled="${entry##*:}"
  [[ "$enabled" -eq 1 ]] || continue
  path="/usr/bin/$bin"
  [[ -x "$path" ]] || continue
  if ! grep -qF "$path" /etc/apparmor.d/local/system_tor 2>/dev/null; then
    echo "${path} Pix," >>/etc/apparmor.d/local/system_tor
  fi
done
apparmor_parser -r /etc/apparmor.d/usr.bin.tor 2>/dev/null || true

echo "[tor-pt] selected=${types#,}"
echo "[tor-pt] obfs4proxy=$(command -v obfs4proxy 2>/dev/null || echo missing)"
echo "[tor-pt] snowflake-client=$(command -v snowflake-client 2>/dev/null || echo missing)"
echo "[tor-pt] webtunnel-client=$(webtunnel_client_path 2>/dev/null || echo missing)"
