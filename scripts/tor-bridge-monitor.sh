#!/usr/bin/env bash
# Fast Tor health check: rotate bridges without re-downloading the full pool.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tor-bridge-lib.sh
source "$SCRIPT_DIR/tor-bridge-lib.sh"

LOG_FILE="${LOG_FILE:-/var/log/olcrtc-bridge-monitor.log}"
FAST_WINDOW="${FAST_WINDOW:-6}"
STATE_FILE="${STATE_FILE:-/var/lib/olcrtc/tor-monitor-state.txt}"

tor_socks_ok() {
  # Fast path: if SOCKS port is down, don't waste time on HTTP.
  timeout 1 bash -lc ':</dev/tcp/127.0.0.1/9050' >/dev/null 2>&1 || return 1
  curl -fsS --max-time 8 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip >/dev/null 2>&1
}

if tor_socks_ok; then
  echo "fails=0" >"$STATE_FILE" 2>/dev/null || true
  bridge_log "monitor: Tor OK — light probe only"
  MAX_PROBE=32 PARALLEL_JOBS=4 RESTART_TOR=0 \
    exec "$SCRIPT_DIR/tor-bridge-pool.sh" --monitor --url-only --no-restart
fi

# Retry once (common: short Tor hiccup / HTTP timeout) before touching bridges.
sleep 2
if tor_socks_ok; then
  echo "fails=0" >"$STATE_FILE" 2>/dev/null || true
  bridge_log "monitor: Tor OK on retry — no rotate"
  exit 0
fi

fails=0
if [[ -f "$STATE_FILE" ]]; then
  fails="$(sed -n 's/^fails=//p' "$STATE_FILE" | head -1)"
fi
fails="$((fails + 1))"
echo "fails=$fails" >"$STATE_FILE" 2>/dev/null || true

if (( fails < 3 )); then
  bridge_log "monitor: Tor down (${fails}/3) — waiting before rotate"
  exit 0
fi

bridge_log "monitor: Tor down (fails=$fails) — fast rotate (window=$FAST_WINDOW)"
FAST_WINDOW="$FAST_WINDOW" exec "$SCRIPT_DIR/tor-bridge-rotate.sh"
