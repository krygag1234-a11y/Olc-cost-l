#!/usr/bin/env bash
# Cloudflare WARP in proxy mode (SOCKS5 on 127.0.0.1:40000 by default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PANEL_ENV=/etc/olcrtc-manager/panel.env
WARP_PROXY="${OLCRTC_WARP_PROXY:-127.0.0.1:40000}"
WARP_MODE="${OLCRTC_WARP_MODE:-proxy}"
WARP_AUTOCONNECT="${OLCRTC_WARP_AUTOCONNECT:-1}"
WARP_PLUS="${OLCRTC_WARP_PLUS:-0}"
WARP_LICENSE="${OLCRTC_WARP_LICENSE:-}"
LOG=/var/log/olcrtc-warp-install.log
ROUTE_SNAPSHOT=/var/lib/olcrtc/warp-route-before.txt

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
install -d /etc/olcrtc-manager /var/log

log() { echo "[warp] $*" | tee -a "$LOG"; }

set_panel_env_key() {
  local key="$1" val="$2"
  install -d /etc/olcrtc-manager
  local lines=()
  if [[ -f "$PANEL_ENV" ]]; then
    mapfile -t lines <"$PANEL_ENV"
  fi
  local found=0 i
  for i in "${!lines[@]}"; do
    if [[ "${lines[$i]}" == "${key}="* ]]; then
      lines[$i]="${key}=${val}"
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    lines+=("${key}=${val}")
  fi
  printf '%s\n' "${lines[@]}" >"$PANEL_ENV"
}

install_package() {
  if command -v warp-cli >/dev/null 2>&1; then
    log "warp-cli already installed"
    return 0
  fi
  log "install cloudflare-warp package"
  apt-get update -qq
  if [[ ! -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg ]]; then
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(. /etc/os-release && echo "${VERSION_CODENAME:-bookworm}") main" \
      >/etc/apt/sources.list.d/cloudflare-client.list
    apt-get update -qq
  fi
  apt-get install -y -qq cloudflare-warp
}

configure_warp() {
  if [[ "$WARP_MODE" != "proxy" ]]; then
    log "WARN: unsafe mode '$WARP_MODE' requested, forcing proxy mode"
    WARP_MODE="proxy"
  fi
  # Safety rail: remember current routing state before touching WARP.
  install -d /var/lib/olcrtc
  ip route show default >"$ROUTE_SNAPSHOT" 2>/dev/null || true
  local before_default
  before_default="$(ip route show default 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//' || true)"

  systemctl enable --now warp-svc 2>/dev/null || true
  sleep 2
  warp-cli registration new 2>/dev/null \
    || warp-cli register accept-tos 2>/dev/null \
    || warp-cli registration show >/dev/null 2>&1 \
    || log "WARN: WARP registration may need manual: warp-cli registration new"
  warp-cli mode "$WARP_MODE" 2>/dev/null || warp-cli set-mode "$WARP_MODE" 2>/dev/null || true
  if [[ "$WARP_PLUS" == "1" && -n "$WARP_LICENSE" ]]; then
    warp-cli registration license "$WARP_LICENSE" 2>/dev/null || warp-cli set-license "$WARP_LICENSE" 2>/dev/null || true
  fi
  if [[ "$WARP_AUTOCONNECT" == "1" ]]; then
    warp-cli connect 2>/dev/null || true
  else
    warp-cli disconnect 2>/dev/null || true
  fi
  set_panel_env_key "OLCRTC_WARP_PROXY" "$WARP_PROXY"
  set_panel_env_key "OLCRTC_WARP_MODE" "$WARP_MODE"
  set_panel_env_key "OLCRTC_WARP_AUTOCONNECT" "$WARP_AUTOCONNECT"
  set_panel_env_key "OLCRTC_WARP_PLUS" "$WARP_PLUS"
  set_panel_env_key "OLCRTC_WARP_LICENSE" "$WARP_LICENSE"
  log "proxy endpoint: $WARP_PROXY"

  # Hard stop guard: WARP must NOT rewrite default route or break SSH plane.
  local after_default
  after_default="$(ip route show default 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//' || true)"
  if [[ -n "$before_default" && -n "$after_default" && "$before_default" != "$after_default" ]]; then
    log "ERROR: default route changed by WARP; rollback to protect SSH"
    warp-cli disconnect 2>/dev/null || true
    systemctl stop warp-svc 2>/dev/null || true
    if [[ -f "$ROUTE_SNAPSHOT" ]]; then
      log "before route: $(cat "$ROUTE_SNAPSHOT" 2>/dev/null || echo n/a)"
    fi
    log "after route:  $after_default"
    return 1
  fi

  # Extra guard: ensure ssh daemon is alive after WARP setup.
  if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
    systemctl is-active ssh.service >/dev/null 2>&1 || {
      log "ERROR: ssh.service inactive after WARP setup; rollback"
      warp-cli disconnect 2>/dev/null || true
      systemctl stop warp-svc 2>/dev/null || true
      return 1
    }
  elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
    systemctl is-active sshd.service >/dev/null 2>&1 || {
      log "ERROR: sshd.service inactive after WARP setup; rollback"
      warp-cli disconnect 2>/dev/null || true
      systemctl stop warp-svc 2>/dev/null || true
      return 1
    }
  fi
}

{
  log "=== install $(date -u -Iseconds) ==="
  install_package
  configure_warp
  if warp-cli status 2>/dev/null | grep -qi connected; then
    log "status: connected"
  else
    log "status: not connected yet (check: warp-cli status)"
  fi
  log "=== done ==="
} >>"$LOG" 2>&1

echo "[warp] installed — proxy $WARP_PROXY (log: $LOG)"
