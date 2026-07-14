#!/usr/bin/env bash
# Remove component packages/artifacts after panel uninstall (not just olc-feature off).
# Usage: olc-component-remove.sh <zapret|tor|split|bridges|warp>
set -euo pipefail

COMPONENT="${1:?component}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
REMOVED_DIR=/var/lib/olcrtc/component-removed
FEATURES="$SCRIPT_DIR/olc-feature.sh"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
install -d "$REMOVED_DIR"

mark_removed() {
  touch "$REMOVED_DIR/$COMPONENT"
}

clear_removed() {
  rm -f "$REMOVED_DIR/$COMPONENT"
}

case "$COMPONENT" in
  zapret)
    bash "$FEATURES" zapret off || true
    systemctl disable zapret.service 2>/dev/null || true
    systemctl stop zapret.service 2>/dev/null || true
    pkill -9 nfqws 2>/dev/null || true
    if [[ -d /opt/zapret ]]; then
      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      mv /opt/zapret "/opt/zapret.uninstalled.${ts}" 2>/dev/null || rm -rf /opt/zapret
    fi
  ;;
  warp)
    bash "$FEATURES" warp off || true
    warp-cli disconnect 2>/dev/null || true
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable warp-svc 2>/dev/null || true
    export DEBIAN_FRONTEND=noninteractive
    timeout 300 apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      remove --purge cloudflare-warp 2>/dev/null || true
    rm -rf /var/lib/cloudflare-warp 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/cloudflare-client.list \
      /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null || true
  ;;
  tor)
    bash "$FEATURES" tor off || true
    bash "$FEATURES" split off 2>/dev/null || true
    bash "$FEATURES" webtunnel off 2>/dev/null || true
    mark_removed
  ;;
  split)
    bash "$FEATURES" split off || true
    if [[ -d /var/lib/olcrtc/lists ]]; then
      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      mv /var/lib/olcrtc/lists "/var/lib/olcrtc/lists.uninstalled.${ts}" 2>/dev/null \
        || rm -rf /var/lib/olcrtc/lists
    fi
  ;;
  bridges)
    bash "$FEATURES" webtunnel off || true
    for u in olcrtc-tor-bridge-monitor olcrtc-tor-bridge-pool olcrtc-tor-bridge-deep; do
      systemctl stop "${u}.timer" 2>/dev/null || true
      systemctl disable "${u}.timer" 2>/dev/null || true
      systemctl stop "${u}.service" 2>/dev/null || true
    done
    rm -f /usr/bin/webtunnel-client /usr/local/bin/webtunnel-client 2>/dev/null || true
    if [[ -f /etc/tor/bridges.conf ]]; then
      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      cp -a /etc/tor/bridges.conf "/etc/tor/bridges.conf.uninstalled.${ts}" 2>/dev/null || true
      : > /etc/tor/bridges.conf
    fi
    mark_removed
  ;;
  *)
    echo "unknown component: $COMPONENT" >&2
    exit 1
    ;;
esac

echo "[component-remove] $COMPONENT artifacts removed"
