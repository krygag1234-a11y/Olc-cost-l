#!/usr/bin/env bash
# Restart Tor + OlcRTC after network/VPS restore (dynamic IP, intermittent link).
set -euo pipefail

log() { echo "[$(date -Iseconds)] $*"; }

log "network-recovery: rotate bridges + restart Tor"
/opt/olcrtc/scripts/tor-bridge-rotate.sh --no-restart 2>/dev/null || true
systemctl reset-failed tor@default 2>/dev/null || true
systemctl restart tor@default.service || true
sleep 3

for i in $(seq 1 30); do
  if curl -fsS --max-time 2 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip >/dev/null 2>&1; then
    log "Tor SOCKS ready"
    break
  fi
  sleep 2
done

if curl -fsS --max-time 5 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip >/dev/null 2>&1; then
  log "Tor OK — restarting olcrtc-manager (SOCKS exit enabled)"
else
  log "Tor not ready — restarting olcrtc-manager without waiting (Jitsi works, no Tor exit)"
fi
systemctl restart olcrtc-manager.service || true
log "done"
