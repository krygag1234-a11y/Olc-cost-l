#!/usr/bin/env bash
# Reversibly detach an optional module selected in the panel.
# User configuration is archived/preserved; reinstall can attach it again.
set -euo pipefail

COMPONENT="${1:?component}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVED_DIR=/var/lib/olcrtc/component-removed
ARCHIVE_DIR=/var/lib/olcrtc/component-archives
FEATURES="$SCRIPT_DIR/olc-feature.sh"
ts="$(date -u +%Y%m%dT%H%M%SZ)"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
install -d "$REMOVED_DIR" "$ARCHIVE_DIR/$COMPONENT/$ts"

archive_move() {
  local src="$1"
  [[ -e "$src" ]] || return 0
  mv "$src" "$ARCHIVE_DIR/$COMPONENT/$ts/"
}

case "$COMPONENT" in
  zapret)
    bash "$FEATURES" zapret off || true
    systemctl disable zapret.service 2>/dev/null || true
    systemctl stop zapret.service 2>/dev/null || true
    pkill -9 nfqws 2>/dev/null || true
    archive_move /opt/zapret
    ;;
  warp)
    bash "$FEATURES" warp off || true
    warp-cli disconnect 2>/dev/null || true
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable warp-svc 2>/dev/null || true
    archive_move /var/lib/cloudflare-warp
    export DEBIAN_FRONTEND=noninteractive
    timeout 300 apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold       remove cloudflare-warp 2>/dev/null || true
    ;;
  tor)
    bash "$FEATURES" tor off || true
    bash "$FEATURES" split off 2>/dev/null || true
    bash "$FEATURES" bridges off 2>/dev/null || true
    ;;
  split)
    bash "$FEATURES" split off || true
    archive_move /var/lib/olcrtc/lists
    ;;
  bridges)
    bash "$FEATURES" bridges off || true
    for u in olcrtc-tor-bridge-monitor olcrtc-tor-bridge-pool olcrtc-tor-bridge-deep; do
      systemctl stop "${u}.timer" 2>/dev/null || true
      systemctl disable "${u}.timer" 2>/dev/null || true
      systemctl stop "${u}.service" 2>/dev/null || true
    done
    # Transport binaries and bridge profiles are submodule state: preserve them.
    [[ -f /etc/tor/bridges.conf ]] && cp -a /etc/tor/bridges.conf "$ARCHIVE_DIR/$COMPONENT/$ts/"
    ;;
  *)
    echo "unknown component: $COMPONENT" >&2
    exit 1
    ;;
esac

printf '%s
' "$ts" >"$REMOVED_DIR/$COMPONENT"
echo "[component-remove] $COMPONENT detached; configuration archive: $ARCHIVE_DIR/$COMPONENT/$ts"
