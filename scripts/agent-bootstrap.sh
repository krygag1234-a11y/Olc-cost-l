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

log() { echo "==> $*"; }

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
    patch ${ENABLE_TOR:+tor obfs4proxy apparmor-utils}
  if [[ "$ENABLE_TOR" -eq 1 ]] && [[ ! -x /usr/bin/webtunnel-client ]]; then
    command -v go >/dev/null || apt-get install -y -qq golang-go
  fi
}

build_webtunnel() {
  [[ "$ENABLE_TOR" -eq 1 ]] || return 0
  [[ -x /usr/bin/webtunnel-client ]] && return 0
  log "webtunnel-client"
  local wt="/tmp/webtunnel"
  rm -rf "$wt"
  git clone --depth 1 https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/webtunnel.git "$wt"
  (cd "$wt/client" && go build -o /usr/bin/webtunnel-client .)
}

setup_tor() {
  [[ "$ENABLE_TOR" -eq 1 ]] || { log "skip Tor (--no-tor / foreign VPS)"; return 0; }
  bash "$SCRIPT_DIR/secure-local-tor.sh" 2>/dev/null || true
  log "Tor bridges pool"
  BRIDGE_TYPES=webtunnel,obfs4 \
  bash "$SCRIPT_DIR/tor-bridge-pool.sh" --fetch --url-only --jobs 6 --target 12 --types webtunnel || \
    bash "$SCRIPT_DIR/tor-bridge-rotate.sh" || true
  mkdir -p /etc/apparmor.d/local
  if ! grep -q webtunnel-client /etc/apparmor.d/local/system_tor 2>/dev/null; then
    echo '/usr/bin/webtunnel-client Pix,' >>/etc/apparmor.d/local/system_tor
    apparmor_parser -r /etc/apparmor.d/usr.bin.tor 2>/dev/null || true
  fi
  systemctl enable tor@default.service
  systemctl restart tor@default.service || true
  systemctl enable olcrtc-tor-bridge-pool.timer olcrtc-tor-bridge-monitor.timer 2>/dev/null || true
}

setup_split_routing() {
  if [[ "$RU_VPS" -ne 1 || "$ENABLE_SPLIT" -ne 1 || "$ENABLE_TOR" -ne 1 ]]; then
    log "skip split lists (foreign VPS or --no-split or --no-tor)"
    return 0
  fi
  OLCRTC_RU_VPS=1 bash "$SCRIPT_DIR/setup-split-ru.sh"
}

setup_sysctl() {
  cat >/etc/sysctl.d/99-olcrtc-performance.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
  sysctl --system >/dev/null 2>&1 || true
}

write_manager_unit() {
  local tor_env=""
  [[ "$ENABLE_TOR" -eq 1 ]] && tor_env=$'Environment=OLCRTC_EXIT_PROXY=127.0.0.1:9050\n'
  local tor_after=""
  [[ "$ENABLE_TOR" -eq 1 ]] && tor_after=$'After=network-online.target tor@default.service\nWants=network-online.target tor@default.service\n'

  cat >/etc/systemd/system/olcrtc-manager.service <<EOF
[Unit]
Description=OlcRTC Manager Panel (patched)
${tor_after}

[Service]
Type=simple
EnvironmentFile=-/etc/olcrtc-manager/panel.env
Environment=OLCRTC_PATH=/usr/local/bin/olcrtc
Environment=OLCRTC_MANAGER_ADDR=0.0.0.0
Environment=OLCRTC_HOST_NETWORK=1
${tor_env}ExecStart=/usr/local/bin/olcrtc-manager -config /etc/olcrtc-manager/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
}

setup_systemd() {
  install -d /etc/olcrtc-manager
  [[ -f /etc/olcrtc-manager/config.json ]] || cat >/etc/olcrtc-manager/config.json <<'EOF'
{"version":1,"name":"olcrtc-vps","port":8888,"clients":[]}
EOF
  write_manager_unit
  cat >/etc/systemd/system/olcrtc-network-recovery.service <<'EOF'
[Unit]
Description=OlcRTC network recovery
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/olcrtc/scripts/network-recovery.sh
EOF
  systemctl daemon-reload
  systemctl enable olcrtc-manager.service olcrtc-network-recovery.service
}

setup_cron() {
  grep -qF healthcheck.sh /etc/crontab 2>/dev/null || \
    echo '*/10 * * * * root /opt/olcrtc/scripts/healthcheck.sh' >>/etc/crontab
}

# --- main ---
require_root
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

if [[ "$REBUILD_ONLY" -eq 1 ]]; then
  BUILD=1 bash "$PATCH_SCRIPT"
  systemctl restart olcrtc-manager
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
    log "Split: RU CIDR + CDN + RU player CDN → direct; rest → Tor"
  elif [[ "$ENABLE_SPLIT" -eq 0 ]]; then
    log "Split: disabled (--no-split), all via Tor exit"
  fi
fi
log "Olcbox: https://github.com/alananisimov/olcbox/releases (nightly: .../tag/nightly)"
log "Set OLCRTC_PUBLIC_URL in panel.env (DDNS, not raw IP)"
