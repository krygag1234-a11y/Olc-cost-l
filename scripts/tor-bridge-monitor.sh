#!/usr/bin/env bash
# Fast Tor health check: rotate bridges without re-downloading the full pool.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tor-bridge-lib.sh
source "$SCRIPT_DIR/tor-bridge-lib.sh"

LOG_FILE="${LOG_FILE:-/var/log/olcrtc-bridge-monitor.log}"
FAST_WINDOW="${FAST_WINDOW:-6}"

tor_socks_ok() {
  curl -fsS --max-time 4 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip >/dev/null 2>&1
}

if tor_socks_ok; then
  bridge_log "monitor: Tor OK — light probe only"
  MAX_PROBE=32 PARALLEL_JOBS=4 RESTART_TOR=0 \
    exec "$SCRIPT_DIR/tor-bridge-pool.sh" --monitor --url-only --no-restart
fi

bridge_log "monitor: Tor down — fast rotate (window=$FAST_WINDOW)"
FAST_WINDOW="$FAST_WINDOW" exec "$SCRIPT_DIR/tor-bridge-rotate.sh"
