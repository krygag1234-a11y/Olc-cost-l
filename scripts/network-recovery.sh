#!/usr/bin/env bash
# Restart Tor only when SOCKS exit is down (do not disturb working Tor).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${LOG_FILE:-/var/log/olcrtc-healthcheck.log}"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }

tor_socks_ok() {
  timeout 1 bash -lc ':</dev/tcp/127.0.0.1/9050' >/dev/null 2>&1 || return 1
  curl -fsS --max-time 10 --socks5-hostname 127.0.0.1:9050 \
    https://check.torproject.org/api/ip >/dev/null 2>&1
}

if tor_socks_ok; then
  log "network-recovery: Tor already OK — skip"
  exit 0
fi

log "network-recovery: Tor down — rotate bridges + restart Tor"
"$SCRIPT_DIR/tor-bridge-rotate.sh" --no-restart 2>/dev/null || true
systemctl reset-failed tor@default 2>/dev/null || true
systemctl restart tor@default.service || true

for i in $(seq 1 30); do
  if tor_socks_ok; then
    log "network-recovery: Tor SOCKS ready (${i})"
    exit 0
  fi
  sleep 2
done

log "network-recovery: Tor still not ready after restart"
exit 1
