#!/usr/bin/env bash
# Tor SOCKS только с localhost (не «голый» SOCKS в интернет). Append-only torrc.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

TORRC="${TORRC:-/etc/tor/torrc}"
[[ "$TORRC" == /etc/tor/torrc ]] || {
  echo "REFUSE TORRC=$TORRC (only /etc/tor/torrc allowed)" >&2
  exit 1
}

safety_torrc_local_socks_only "$TORRC"
systemctl restart tor@default 2>/dev/null || true
echo "Tor SocksPolicy: only 127.0.0.1 / ::1"
