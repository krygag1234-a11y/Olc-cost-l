#!/usr/bin/env bash
# Install obfs4proxy, snowflake-client; ensure webtunnel-client exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

apt-get update -qq
apt-get install -y -qq obfs4proxy snowflake-client apparmor-utils 2>/dev/null || \
  apt-get install -y -qq obfs4proxy apparmor-utils

if [[ ! -x /usr/bin/webtunnel-client ]] && [[ ! -x /usr/local/bin/webtunnel-client ]]; then
  command -v go >/dev/null || apt-get install -y -qq golang-go
  wt=/tmp/webtunnel-build
  rm -rf "$wt"
  git clone --depth 1 https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/webtunnel.git "$wt"
  (cd "$wt/client" && go build -o /usr/bin/webtunnel-client .)
fi

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
echo "[tor-pt] webtunnel-client=$(command -v webtunnel-client 2>/dev/null || ls /usr/local/bin/webtunnel-client 2>/dev/null || echo missing)"
