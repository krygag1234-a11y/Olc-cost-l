#!/usr/bin/env bash
# Apply zapret config preset and restart nfqws.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
STRATEGY="${1:-}"
STATE=/etc/olcrtc-manager/zapret.strategy
OPT=/opt/zapret

[[ -n "$STRATEGY" ]] || { echo "usage: olc-zapret-apply-strategy.sh <strategy_id>" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || exec sudo -E bash "$0" "$@"

log() { echo "[zapret-strategy] $*"; }

resolve_config() {
  local id="$1"
  case "$id" in
    olcrtc-minimal)
      echo "$REPO_ROOT/data/zapret-olcrtc.config"
      ;;
    z4r-default|z4r-config.default)
      echo "$REPO_ROOT/data/zapret4rocket/config.default"
      ;;
    *)
      if [[ -f "$REPO_ROOT/data/zapret-strategies/${id}.config" ]]; then
        echo "$REPO_ROOT/data/zapret-strategies/${id}.config"
        return 0
      fi
      return 1
      ;;
  esac
}

cfg="$(resolve_config "$STRATEGY")" || {
  log "unknown strategy: $STRATEGY"
  exit 1
}
[[ -f "$cfg" ]] || {
  log "config missing: $cfg (run sync-zapret4rocket.sh?)"
  exit 1
}

install -d /etc/olcrtc-manager
echo "$STRATEGY" >"$STATE"
install -m 0644 "$cfg" "$OPT/config"
log "applied $STRATEGY → $OPT/config"

if [[ -x "$OPT/init.d/sysv/zapret" ]]; then
  "$OPT/init.d/sysv/zapret" restart || systemctl restart zapret.service 2>/dev/null || true
elif systemctl is-active zapret.service &>/dev/null; then
  systemctl restart zapret.service
fi

if pidof nfqws >/dev/null 2>&1; then
  log "ok nfqws running"
else
  log "WARN: nfqws not running after restart"
  exit 1
fi
