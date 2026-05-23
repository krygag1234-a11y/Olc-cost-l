#!/usr/bin/env bash
# Cron: verify Tor + panel; recover only when Tor is actually down.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${LOG_FILE:-/var/log/olcrtc-healthcheck.log}"
TOR_RETRIES="${TOR_RETRIES:-2}"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }

tor_socks_ok() {
  timeout 1 bash -lc ':</dev/tcp/127.0.0.1/9050' >/dev/null 2>&1 || return 1
  curl -fsS --max-time 10 --socks5-hostname 127.0.0.1:9050 \
    https://check.torproject.org/api/ip >/dev/null 2>&1
}

panel_ok() {
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8888/admin 2>/dev/null || echo 000)"
  [[ "$code" =~ ^(200|302|303|307|308)$ ]]
}

TOR_OK=0
PANEL_OK=0
for _ in $(seq 1 "$TOR_RETRIES"); do
  tor_socks_ok && TOR_OK=1 && break
  sleep 2
done
panel_ok && PANEL_OK=1

if [[ "$TOR_OK" -eq 0 ]] && systemctl is-enabled tor@default &>/dev/null; then
  log "healthcheck: Tor down — rotate + apply"
  FAST_WINDOW=6 "$SCRIPT_DIR/tor-bridge-rotate.sh" --no-restart >>"$LOG" 2>&1 || true
  if ! tor_socks_ok; then
    MAX_PROBE=48 PARALLEL_JOBS=6 RESTART_TOR=1 \
      "$SCRIPT_DIR/tor-bridge-pool.sh" --apply --url-only --jobs 6 --target 10 >>"$LOG" 2>&1 || true
  fi
  if ! tor_socks_ok; then
    log "healthcheck: Tor still down — network-recovery"
    "$SCRIPT_DIR/network-recovery.sh" >>"$LOG" 2>&1 || true
  else
    log "healthcheck: Tor recovered after bridge apply"
  fi
elif [[ "$PANEL_OK" -eq 0 ]]; then
  log "healthcheck: panel not responding — restart olcrtc-manager only"
  systemctl restart olcrtc-manager.service 2>/dev/null || true
fi
