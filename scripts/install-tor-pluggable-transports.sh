#!/usr/bin/env bash
# Install obfs4proxy, snowflake-client; try webtunnel-client (optional).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=lib-webtunnel-build.sh
source "$SCRIPT_DIR/lib-webtunnel-build.sh"

apt-get update -qq
apt-get install -y -qq obfs4proxy snowflake-client apparmor-utils curl 2>/dev/null || \
  apt-get install -y -qq obfs4proxy apparmor-utils curl

build_webtunnel_client echo || true

mkdir -p /etc/apparmor.d/local
for bin in webtunnel-client snowflake-client obfs4proxy; do
  path="/usr/bin/$bin"
  [[ -x "$path" ]] || continue
  if ! grep -qF "$path" /etc/apparmor.d/local/system_tor 2>/dev/null; then
    echo "${path} Pix," >>/etc/apparmor.d/local/system_tor
  fi
done
apparmor_parser -r /etc/apparmor.d/usr.bin.tor 2>/dev/null || true

echo "[tor-pt] obfs4proxy=$(command -v obfs4proxy 2>/dev/null || echo missing)"
echo "[tor-pt] snowflake-client=$(command -v snowflake-client 2>/dev/null || echo missing)"
echo "[tor-pt] webtunnel-client=$(webtunnel_client_path 2>/dev/null || echo missing)"
if ! webtunnel_client_ready; then
  echo "[tor-pt] hint: BRIDGE_TYPES=obfs4 or retry when gitlab.torproject.org is reachable"
fi
