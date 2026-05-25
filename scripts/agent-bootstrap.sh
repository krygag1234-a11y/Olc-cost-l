#!/usr/bin/env bash
# Flexible VPS deploy for OlcRTC + manager (patched) + optional Tor/split.
#
# Usage:
#   agent-bootstrap.sh --full              # clean VPS: deps + patched build + all services
#   agent-bootstrap.sh                     # config only (tor/panel already built)
#   agent-bootstrap.sh --no-tor            # иностранный VPS: только панель+olcrtc, без Tor/split/мостов
#   agent-bootstrap.sh --with-tor          # RU VPS: Tor + bridge pool + split (RU+CDN+плееры)
#   agent-bootstrap.sh --no-split          # RU VPS: Tor без списков direct (весь трафик через exit)
#   agent-bootstrap.sh --foreign           # то же что --no-tor (явно не-RU)
#   agent-bootstrap.sh --rebuild-only      # only apply patches + rebuild binaries
#   agent-bootstrap.sh --update            # git pull path: lists + patches + tor exit (no apt)
#   agent-bootstrap.sh --help
#
# Env: OLCRTC_ENABLE_TOR=0|1  OLCRTC_ENABLE_SPLIT=0|1  OLCRTC_RU_VPS=0|1  OLCRTC_BRANCH=master
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DOC="$REPO_ROOT/docs/VPS-SETUP.md"
PATCH_SCRIPT="$SCRIPT_DIR/apply-olcrtc-patches.sh"
export OLC_REPO_ROOT="$REPO_ROOT"

FULL=0
ENABLE_TOR="${OLCRTC_ENABLE_TOR:-1}"
ENABLE_SPLIT="${OLCRTC_ENABLE_SPLIT:-1}"
RU_VPS="${OLCRTC_RU_VPS:-1}"
REBUILD_ONLY=0
UPDATE=0

log() { echo "==> $*"; }

# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"
# shellcheck source=lib-webtunnel-build.sh
source "$SCRIPT_DIR/lib-webtunnel-build.sh"

ensure_install_symlink() {
  safety_ensure_olcrtc_symlink "$REPO_ROOT"
}

usage() {
  sed -n '3,14p' "$0"
  echo ""
  echo "Patches: $REPO_ROOT/patches/PATCHES.md"
  echo "olcrtc:  master | panel: main | Olcbox: releases/tag/nightly"
  echo "Client:  https://github.com/alananisimov/olcbox/releases"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL=1 ;;
    --no-tor|--foreign) ENABLE_TOR=0; ENABLE_SPLIT=0; RU_VPS=0 ;;
    --with-tor) ENABLE_TOR=1; RU_VPS=1 ;;
    --no-split) ENABLE_SPLIT=0; RU_VPS=1 ;;
    --ru) RU_VPS=1; ENABLE_TOR=1; ENABLE_SPLIT=1 ;;
    --rebuild-only) REBUILD_ONLY=1 ;;
    --update) UPDATE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
}

install_deps() {
  log "packages"
  apt-get update -qq
  apt-get install -y -qq git curl build-essential golang-go jq ca-certificates \
    patch ${ENABLE_TOR:+tor obfs4proxy snowflake-client apparmor-utils ffmpeg}
  bash "$SCRIPT_DIR/install-go-toolchain.sh"
  export PATH="/usr/local/go/bin:${PATH:-}"
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
  if [[ "$ENABLE_TOR" -eq 1 ]] && [[ ! -x /usr/bin/webtunnel-client ]]; then
    command -v go >/dev/null || apt-get install -y -qq golang-go
  fi
}

build_webtunnel() {
  [[ "$ENABLE_TOR" -eq 1 ]] || return 0
  log "webtunnel-client (optional — obfs4/snowflake work without it)"
  build_webtunnel_client log || true
}

setup_tor() {
  [[ "$ENABLE_TOR" -eq 1 ]] || { log "skip Tor (--no-tor / foreign VPS)"; return 0; }
  bash "$SCRIPT_DIR/secure-local-tor.sh" 2>/dev/null || true
  bash "$SCRIPT_DIR/install-tor-pluggable-transports.sh" 2>/dev/null || true
  local btypes
  btypes="$(effective_bridge_types "${BRIDGE_TYPES:-webtunnel,obfs4}")"
  if ! webtunnel_client_ready; then
    log "Tor bridges: obfs4-only (webtunnel-client not built — gitlab often times out from RU)"
  else
    log "Tor bridges pool ($btypes)"
  fi
  export BRIDGE_TYPES="$btypes"
  bash "$SCRIPT_DIR/fetch-bridge-extra-sources.sh" 2>/dev/null || \
    bash "$SCRIPT_DIR/tor-bridge-pool.sh" --fetch --url-only --jobs 6 --target 12 --types "$btypes" || \
    bash "$SCRIPT_DIR/tor-bridge-rotate.sh" || true
  bash "$SCRIPT_DIR/tor-bridge-pool.sh" --apply --types "$btypes" 2>/dev/null || true
  systemctl enable tor@default.service
  systemctl restart tor@default.service || true
  systemctl enable olcrtc-tor-bridge-pool.timer olcrtc-tor-bridge-monitor.timer \
    olcrtc-tor-bridge-deep.timer 2>/dev/null || true
  bash "$SCRIPT_DIR/configure-tor-exit.sh" 2>/dev/null || true
}

setup_split_routing() {
  if [[ "$RU_VPS" -ne 1 || "$ENABLE_SPLIT" -ne 1 || "$ENABLE_TOR" -ne 1 ]]; then
    log "skip split lists (foreign VPS or --no-split or --no-tor)"
    return 0
  fi
  OLCRTC_RU_VPS=1 bash "$SCRIPT_DIR/setup-split-ru.sh"
}

setup_sysctl() {
  local f=/etc/sysctl.d/99-olcrtc-performance.conf
  safety_path_allowed "$f" || return 1
  cat >"$f" <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.core.rmem_default=2097152
net.core.wmem_default=2097152
net.ipv4.tcp_rmem=4096 1048576 33554432
net.ipv4.tcp_wmem=4096 1048576 33554432
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.core.netdev_max_backlog=250000
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
EOF
  # Only our drop-in — do not reload unrelated sysctl.d on shared hosts
  sysctl -p "$f" >/dev/null 2>&1 || true
}

install_systemd_units() {
  local scripts="${REPO_ROOT}/scripts"
  cp "$REPO_ROOT/packaging/systemd/olcrtc-manager.service" /etc/systemd/system/olcrtc-manager.service
  if [[ "$ENABLE_TOR" -ne 1 ]]; then
    sed -i '/tor@default\.service/d; /^Environment=OLCRTC_EXIT_PROXY=/d' \
      /etc/systemd/system/olcrtc-manager.service
  fi

  for u in olcrtc-tor-bridge-pool olcrtc-tor-bridge-monitor olcrtc-tor-bridge-deep; do
    [[ "$ENABLE_TOR" -eq 1 ]] || continue
    sed "s|@OLC_SCRIPTS@|${scripts}|g" \
      "$REPO_ROOT/packaging/systemd/${u}.service" \
      >/etc/systemd/system/${u}.service
    install -m 0644 "$REPO_ROOT/packaging/systemd/${u}.timer" \
      "/etc/systemd/system/${u}.timer"
  done

  cat >/etc/systemd/system/olcrtc-network-recovery.service <<EOF
[Unit]
Description=OlcRTC network recovery
After=network-online.target

[Service]
Type=oneshot
ExecStart=${scripts}/network-recovery.sh
EOF
}

setup_systemd() {
  install -d /etc/olcrtc-manager
  [[ -f /etc/olcrtc-manager/config.json ]] || cat >/etc/olcrtc-manager/config.json <<'EOF'
{"version":1,"name":"olcrtc-vps","port":8888,"clients":[]}
EOF
  install_systemd_units
  systemctl daemon-reload
  systemctl enable olcrtc-manager.service olcrtc-network-recovery.service
}

setup_cron() {
  local cronf=/etc/cron.d/olcrtc-healthcheck
  safety_path_allowed "$cronf" || return 1
  cat >"$cronf" <<EOF
# Olc-cost-l — healthcheck (safe to delete this file to disable)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/10 * * * * root ${REPO_ROOT}/scripts/healthcheck.sh >>/var/log/olcrtc-healthcheck.log 2>&1
# After split list refresh (Sun 04:10) — sync zapret exclusions without full reinstall
10 4 * * 0 root ${REPO_ROOT}/scripts/setup-split-ru.sh >>/var/log/olcrtc-zapret-sync.log 2>&1
EOF
  chmod 0644 "$cronf"
  # Remove legacy line from /etc/crontab if present (older deploys)
  if grep -qF 'healthcheck.sh' /etc/crontab 2>/dev/null; then
    sed -i '\|healthcheck\.sh|d' /etc/crontab
  fi
}

# --- main ---
require_root
ensure_install_symlink
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

if [[ "$REBUILD_ONLY" -eq 1 ]]; then
  BUILD=1 bash "$PATCH_SCRIPT"
  systemctl restart olcrtc-manager
  exit 0
fi

setup_zapret() {
  [[ "${OLCRTC_ENABLE_ZAPRET:-1}" -eq 1 ]] || return 0
  [[ "$RU_VPS" -eq 1 ]] || return 0
  if [[ "${OLCRTC_ZAPRET_REINSTALL:-0}" != "1" ]] && [[ -x /opt/zapret/nfq/nfqws ]] && pidof nfqws >/dev/null 2>&1; then
    log "zapret: sync excludes from split lists + carriers (set OLCRTC_ZAPRET_REINSTALL=1 for full reinstall)"
    bash "$SCRIPT_DIR/zapret-sync-excludes.sh" --reload-zapret || true
    return 0
  fi
  log "zapret (direct egress DPI — may take several minutes on first install)"
  bash "$SCRIPT_DIR/tor-bridge-pool.sh" --jobs 8 --target 10 2>/dev/null || true
  systemctl restart tor@default 2>/dev/null || true
  export OLCRTC_ZAPRET_FULL="${OLCRTC_ZAPRET_FULL:-1}"
  bash "$SCRIPT_DIR/install-zapret-vps.sh" || log "WARN: zapret install failed — retry manually"
}

if [[ "$UPDATE" -eq 1 ]]; then
  log "UPDATE: refresh lists, patches, tor exit, zapret, units"
  BUILD=1 bash "$PATCH_SCRIPT"
  setup_sysctl
  setup_tor
  setup_split_routing
  bash "$SCRIPT_DIR/fetch-zapret-community-excludes.sh" 2>/dev/null || true
  setup_zapret
  setup_systemd
  setup_cron
  find /tmp -maxdepth 1 -name 'olcrtc-manager-srv-*.yaml' -delete 2>/dev/null || true
  systemctl restart olcrtc-manager
  log "Update done."
  exit 0
fi

if [[ "$FULL" -eq 1 ]]; then
  install_deps
  BUILD=1 bash "$PATCH_SCRIPT"
  build_webtunnel
  setup_sysctl
else
  # ensure patched binaries exist
  if [[ ! -x /usr/local/bin/olcrtc ]] || [[ ! -x /usr/local/bin/olcrtc-manager ]]; then
    log "binaries missing — building patched versions"
    BUILD=1 bash "$PATCH_SCRIPT"
    build_webtunnel
  fi
fi

setup_tor
setup_split_routing
bash "$SCRIPT_DIR/fetch-zapret-community-excludes.sh" 2>/dev/null || true
setup_zapret
setup_systemd
setup_cron
systemctl enable --now olcrtc-manager 2>/dev/null || systemctl restart olcrtc-manager

log "Done. Read $DOC"
log "Patches: $REPO_ROOT/patches/PATCHES.md"
if [[ "$ENABLE_TOR" -eq 0 ]]; then
  log "Mode: FOREIGN / NO TOR — panel only, no bridges, no split scripts"
else
  log "Mode: Tor + bridge pool (RU VPS)"
  if [[ "$RU_VPS" -eq 1 && "$ENABLE_SPLIT" -eq 1 ]]; then
    log "Split: *.ru + players + RF-blocked → direct (zapret DPI); force-tor (YT) + rest → Tor"
  elif [[ "$ENABLE_SPLIT" -eq 0 ]]; then
    log "Split: disabled (--no-split), all via Tor exit"
  fi
fi
log "Olcbox: https://github.com/alananisimov/olcbox/releases (nightly: .../tag/nightly)"
log "Set OLCRTC_PUBLIC_URL in panel.env (DDNS, not raw IP)"
