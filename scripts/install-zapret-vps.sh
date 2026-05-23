#!/usr/bin/env bash
# Install zapret on RU VPS for olcrtc DIRECT egress (DPI bypass).
# OLCRTC_ZAPRET_FULL=1 → zapret4rocket config.default (recommended on 4+ GB RAM).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

ZAPRET_VER="${ZAPRET_VER:-72.12}"
Z4R_SRC="${Z4R_SRC:-$REPO_ROOT/data/zapret4rocket}"
Z4R_REPO_URL="${Z4R_REPO_URL:-}"
OPT="/opt/zapret"
# Auto full on >=4G RAM unless overridden
if [[ -z "${OLCRTC_ZAPRET_FULL:-}" ]]; then
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  [[ "$mem_kb" -ge 3500000 ]] && OLCRTC_ZAPRET_FULL=1 || OLCRTC_ZAPRET_FULL=0
fi

log() { echo "[install-zapret] $*"; }

install_deps() {
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl iptables ipset build-essential libnetfilter-queue-dev libcap-dev \
    libmnl-dev zlib1g-dev libsystemd-dev pkg-config git gzip
}

fetch_zapret() {
  if [[ -x "$OPT/init.d/sysv/zapret" && -x "$OPT/nfq/nfqws" ]]; then
    log "zapret binaries present in $OPT"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  log "download zapret v${ZAPRET_VER}"
  curl -fsSL --max-time 180 \
    "https://github.com/bol-van/zapret/releases/download/v${ZAPRET_VER}/zapret-v${ZAPRET_VER}.tar.gz" \
    | tar -xz -C "$tmp"
  rm -rf "$OPT"
  mv "$tmp/zapret-v${ZAPRET_VER}" "$OPT"
  (cd "$OPT" && sh ./install_bin.sh)
}

ensure_z4r_src() {
  [[ -f "$Z4R_SRC/config.default" ]] && return 0
  if [[ -n "$Z4R_REPO_URL" ]]; then
    log "clone zapret4rocket → $Z4R_SRC"
    rm -rf "$Z4R_SRC"
    git clone --depth 1 "$Z4R_REPO_URL" "$Z4R_SRC"
  fi
  [[ -f "$Z4R_SRC/config.default" ]]
}

apply_z4r_assets() {
  ensure_z4r_src || return 1
  mkdir -p "$OPT/lists" "$OPT/ipset" "$OPT/files/fake"
  [[ -f "$Z4R_SRC/fake_files.tar.gz" ]] && tar -xzf "$Z4R_SRC/fake_files.tar.gz" -C "$OPT/files/fake"
  [[ -d "$Z4R_SRC/lists" ]] && cp -a "$Z4R_SRC/lists/"* "$OPT/lists/" 2>/dev/null || true
  [[ -d "$Z4R_SRC/extra_strats" ]] && cp -a "$Z4R_SRC/extra_strats" "$OPT/"
  touch "$OPT/lists/russia-youtube-rtmps.txt" "$OPT/lists/russia-youtubeQ.txt" \
    "$OPT/lists/russia-youtube.txt" "$OPT/lists/autohostlist.txt" 2>/dev/null || true
}

apply_config() {
  if [[ "$OLCRTC_ZAPRET_FULL" == "1" ]] && apply_z4r_assets; then
    install -m 0644 "$Z4R_SRC/config.default" "$OPT/config"
    log "config: zapret4rocket full (OLCRTC_ZAPRET_FULL=1)"
  else
    [[ "$OLCRTC_ZAPRET_FULL" == "1" ]] && log "WARN: no zapret4rocket at Z4R_SRC — minimal config"
    local cfg="$REPO_ROOT/data/zapret-olcrtc.config"
    install -m 0644 "$cfg" "$OPT/config"
    bash "$SCRIPT_DIR/sync-zapret-hostlist.sh"
    cp /var/lib/olcrtc/zapret-direct-hostlist.txt "$OPT/ipset/zapret-hosts-user.txt"
    log "config: olcrtc minimal"
  fi
}

noninteractive_install() {
  if [[ -f "$OPT/common/installer.sh" ]]; then
    sed -i 's/if \[ -n "\$1" \] || ask_yes_no N "do you want to continue";/if true;/' \
      "$OPT/common/installer.sh" 2>/dev/null || true
  fi
  export INIT_APPLY_FW=1
  cd "$OPT"
  yes "" | timeout 600 sh ./install_easy.sh </dev/null || log "install_easy: non-zero, continuing"
}

enable_service() {
  install -m 0644 "$OPT/init.d/systemd/zapret.service" /etc/systemd/system/zapret.service 2>/dev/null || true
  systemctl daemon-reload
  systemctl enable zapret.service 2>/dev/null || true
  timeout 180 "$OPT/init.d/sysv/zapret" restart || systemctl restart zapret.service
  if pidof nfqws >/dev/null; then
    log "nfqws running: $(pidof nfqws)"
  else
    log "WARN: nfqws not running"
    return 1
  fi
}

main() {
  safety_require_root
  install_deps
  fetch_zapret
  apply_config
  noninteractive_install
  enable_service
  log "done (full=$OLCRTC_ZAPRET_FULL) — zapret on direct egress; Tor 127.0.0.1:9050"
}

main "$@"
