#!/usr/bin/env bash
# Full removal of Olc-cost-l / olcrtc-manager / olcrtc stack from this host.
# Safe to run after failed install or for clean re-test.
#
# Usage (from repo root or anywhere):
#   sudo bash /opt/Olc-cost-l/scripts/olc-purge.sh
#   sudo bash /opt/Olc-cost-l/scripts/olc-purge.sh --keep-tor   # leave tor@default + bridges
#   sudo bash /opt/Olc-cost-l/scripts/olc-purge.sh --purge-repo # also remove /opt/Olc-cost-l
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

KEEP_TOR=0
PURGE_REPO=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-tor) KEEP_TOR=1 ;;
    --purge-repo) PURGE_REPO=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
  shift
done

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

log() { echo "[purge] $*"; }

if [[ -f "$SCRIPT_DIR/lib-disk-preflight.sh" ]]; then
  # shellcheck source=lib-disk-preflight.sh
  source "$SCRIPT_DIR/lib-disk-preflight.sh"
  olc_preflight_disk_space "purge" || exit 1
fi
if [[ -f "$SCRIPT_DIR/lib-cache-cleanup.sh" ]]; then
  # shellcheck source=lib-cache-cleanup.sh
  source "$SCRIPT_DIR/lib-cache-cleanup.sh"
fi
if [[ -f "$SCRIPT_DIR/lib-vps-backup.sh" ]]; then
  # shellcheck source=lib-vps-backup.sh
  source "$SCRIPT_DIR/lib-vps-backup.sh"
  # Skip backup creation during purge to avoid hanging on large backup dirs
  export OLC_VPS_BACKUP_DISABLE=1
fi

stop_unit() {
  local u="$1"
  systemctl stop "$u" 2>/dev/null || true
  systemctl disable "$u" 2>/dev/null || true
}

log "stop services"
stop_unit olcrtc-manager.service
stop_unit olcrtc-network-recovery.service
for u in olcrtc-tor-bridge-pool olcrtc-tor-bridge-monitor olcrtc-tor-bridge-deep; do
  stop_unit "${u}.timer"
  stop_unit "${u}.service"
done
# zapret if we installed it
stop_unit zapret.service
stop_unit zapret4rocket.service 2>/dev/null || true

log "kill olcrtc processes"
if [[ "$DRY_RUN" -eq 0 ]]; then
  pkill -f '/usr/local/bin/olcrtc-manager' 2>/dev/null || true
  pkill -f '/usr/local/bin/olcrtc ' 2>/dev/null || true
  sleep 1
  pkill -9 -f '/usr/local/bin/olcrtc' 2>/dev/null || true
fi

log "remove systemd units"
for f in \
  /etc/systemd/system/olcrtc-manager.service \
  /etc/systemd/system/olcrtc-network-recovery.service \
  /etc/systemd/system/olcrtc-tor-bridge-pool.service \
  /etc/systemd/system/olcrtc-tor-bridge-pool.timer \
  /etc/systemd/system/olcrtc-tor-bridge-monitor.service \
  /etc/systemd/system/olcrtc-tor-bridge-monitor.timer \
  /etc/systemd/system/olcrtc-tor-bridge-deep.service \
  /etc/systemd/system/olcrtc-tor-bridge-deep.timer; do
  run rm -f "$f"
done
run systemctl daemon-reload

log "remove cron"
run rm -f /etc/cron.d/olcrtc-healthcheck
if [[ "$DRY_RUN" -eq 0 ]] && grep -qF 'healthcheck.sh' /etc/crontab 2>/dev/null; then
  sed -i '\|healthcheck\.sh|d' /etc/crontab || true
fi

log "remove binaries and config"
run rm -f /usr/local/bin/olcrtc /usr/local/bin/olcrtc-manager
run rm -rf /etc/olcrtc-manager

log "remove runtime state"
run rm -rf /var/lib/olcrtc
run rm -f /var/log/olcrtc-healthcheck.log
run find /tmp -maxdepth 1 -name 'olcrtc-manager-srv-*.yaml' -delete 2>/dev/null || true
run rm -rf /tmp/olcrtc-src /tmp/olcrtc-manager-panel

log "remove build caches"
if [[ "$DRY_RUN" -eq 0 ]] && declare -f olc_cleanup_purge_caches >/dev/null 2>&1; then
  olc_cleanup_purge_caches
fi

log "remove sysctl drop-in"
run rm -f /etc/sysctl.d/99-olcrtc-performance.conf

if [[ "$KEEP_TOR" -eq 0 ]]; then
  log "remove olcrtc tor drop-ins (tor package stays installed)"
  run rm -f /etc/tor/torrc.d/olcrtc-exit.conf
  run rm -f /etc/tor/bridges.conf
  # restore empty bridges only if file was ours (no user bridges)
  if [[ "$DRY_RUN" -eq 0 ]] && [[ -f /etc/tor/torrc ]]; then
    grep -q 'bridges.conf' /etc/tor/torrc 2>/dev/null && \
      sed -i '/^%include.*bridges\.conf/d' /etc/tor/torrc 2>/dev/null || true
  fi
  systemctl restart tor@default 2>/dev/null || true
else
  log "keeping tor@default and /etc/tor/bridges.conf"
fi

run rm -f /opt/olcrtc
if [[ "$PURGE_REPO" -eq 1 ]]; then
  log "remove install dir /opt/Olc-cost-l"
  run rm -rf /opt/Olc-cost-l
else
  log "keeping /opt/Olc-cost-l (use --purge-repo to delete)"
fi

log "done — olcrtc stack removed"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run only; nothing was deleted"
fi
