#!/usr/bin/env bash
# Cron-friendly: verify Tor + panel, restart on failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOR_OK=0
PANEL_OK=0

if curl -fsS --max-time 5 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip >/dev/null 2>&1; then
  TOR_OK=1
fi

if curl -fsS --max-time 3 http://127.0.0.1:8888/ >/dev/null 2>&1; then
  PANEL_OK=1
fi

if [[ "$TOR_OK" -eq 0 ]] && systemctl is-enabled tor@default &>/dev/null; then
  FAST_WINDOW=6 "$SCRIPT_DIR/tor-bridge-rotate.sh" >>/var/log/olcrtc-healthcheck.log 2>&1 || true
  if ! curl -fsS --max-time 5 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip >/dev/null 2>&1; then
    MAX_PROBE=48 PARALLEL_JOBS=6 \
      "$SCRIPT_DIR/tor-bridge-pool.sh" --apply --url-only --jobs 6 --target 10 >>/var/log/olcrtc-healthcheck.log 2>&1 || true
  fi
fi

if [[ "$PANEL_OK" -eq 0 ]]; then
  systemctl restart olcrtc-manager.service 2>/dev/null || true
fi

if [[ "$TOR_OK" -eq 0 || "$PANEL_OK" -eq 0 ]]; then
  "$SCRIPT_DIR/network-recovery.sh" >>/var/log/olcrtc-healthcheck.log 2>&1 || true
fi
