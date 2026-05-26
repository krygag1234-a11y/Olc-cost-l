#!/usr/bin/env bash
# Feature toggles for live VPS (no full reinstall).
#
# Usage:
#   olc-feature status                  # show current toggle state
#   olc-feature zapret on|off|reload
#   olc-feature tor    on|off
#   olc-feature split  on|off           # *.ru/CDN direct lists for olcrtc
#   olc-feature webtunnel on|off|status # try mirror, install/uninstall
#   olc-feature all-off                 # quick: zapret off + tor off + split off (testing)
#   olc-feature all-on                  # restore defaults (zapret + tor + split)
#
# Toggles are stored in /etc/olcrtc-manager/features.env so they survive reboot
# and are sourced by systemd units (Olcrtc manager, healthcheck cron, etc.).
#
# Designed to be safe and reversible:
#   • stops services, doesn't uninstall packages
#   • backs up modified configs to .bak.<ts>
#   • prints a one-liner to revert
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FEATURES_ENV=/etc/olcrtc-manager/features.env
TOR_BRIDGES=/etc/tor/bridges.conf
TOR_BRIDGES_BACKUP_DIR=/var/lib/olcrtc/feature-backups

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
install -d /etc/olcrtc-manager "$TOR_BRIDGES_BACKUP_DIR"
[[ -f "$FEATURES_ENV" ]] || cat >"$FEATURES_ENV" <<'EOF'
# Olc-cost-l feature toggles (managed by /opt/Olc-cost-l/scripts/olc-feature.sh)
# Values: 1 = enabled (default), 0 = disabled
OLCRTC_ENABLE_ZAPRET=1
OLCRTC_ENABLE_TOR=1
OLCRTC_ENABLE_SPLIT=1
OLCRTC_ENABLE_WEBTUNNEL=1
EOF

_now()  { date -u +%Y%m%dT%H%M%SZ; }
_load() { set -a; source "$FEATURES_ENV"; set +a; }
_save() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$FEATURES_ENV"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$FEATURES_ENV"
  else
    echo "${key}=${val}" >> "$FEATURES_ENV"
  fi
}

status() {
  _load
  echo "=== olc-feature status ==="
  printf '  %-10s %s\n' zapret "${OLCRTC_ENABLE_ZAPRET:-1}"
  printf '  %-10s %s\n' tor    "${OLCRTC_ENABLE_TOR:-1}"
  printf '  %-10s %s\n' split  "${OLCRTC_ENABLE_SPLIT:-1}"
  printf '  %-10s %s\n' webtunnel "${OLCRTC_ENABLE_WEBTUNNEL:-1}"
  echo
  echo "Live state:"
  printf '  %-10s ' tor;       systemctl is-active tor@default 2>/dev/null || echo inactive
  printf '  %-10s ' zapret;    systemctl is-active zapret 2>/dev/null || echo inactive
  printf '  %-10s ' nfqws;     pidof nfqws >/dev/null 2>&1 && echo running || echo stopped
  printf '  %-10s ' manager;   systemctl is-active olcrtc-manager 2>/dev/null || echo inactive
  printf '  %-10s ' webtunnel
  if [[ -x /usr/bin/webtunnel-client ]]; then echo "/usr/bin/webtunnel-client present"
  else echo "missing"; fi
}

# ---------- ZAPRET ----------
zapret_on() {
  _save OLCRTC_ENABLE_ZAPRET 1
  if systemctl list-unit-files zapret.service >/dev/null 2>&1; then
    systemctl enable --now zapret.service
  elif [[ -x /opt/zapret/init.d/sysv/zapret ]]; then
    /opt/zapret/init.d/sysv/zapret start
  else
    echo "zapret not installed — run: $REPO_ROOT/scripts/install-zapret-vps.sh"
    return 1
  fi
  echo "[zapret] ON"
}
zapret_off() {
  _save OLCRTC_ENABLE_ZAPRET 0
  systemctl stop zapret.service 2>/dev/null || /opt/zapret/init.d/sysv/zapret stop 2>/dev/null || true
  pkill -9 nfqws 2>/dev/null || true
  echo "[zapret] OFF (config kept, run 'olc-feature zapret on' to restore)"
}
zapret_reload() {
  if [[ -x "$REPO_ROOT/scripts/zapret-sync-excludes.sh" ]]; then
    bash "$REPO_ROOT/scripts/zapret-sync-excludes.sh" --reload-zapret
  fi
}

# ---------- TOR ----------
tor_on() {
  _save OLCRTC_ENABLE_TOR 1
  systemctl enable --now tor@default.service
  # Re-enable EXIT_PROXY for manager
  if [[ -f /etc/systemd/system/olcrtc-manager.service ]]; then
    if ! grep -q 'OLCRTC_EXIT_PROXY=' /etc/systemd/system/olcrtc-manager.service; then
      cp "$REPO_ROOT/packaging/systemd/olcrtc-manager.service" /etc/systemd/system/olcrtc-manager.service
      systemctl daemon-reload
      systemctl restart olcrtc-manager
    fi
  fi
  echo "[tor] ON"
}
tor_off() {
  _save OLCRTC_ENABLE_TOR 0
  # Stop tor but DO NOT remove torrc/bridges (so we can flip back).
  systemctl stop tor@default.service 2>/dev/null || true
  systemctl disable tor@default.service 2>/dev/null || true
  # Manager: remove SOCKS dependency so it doesn't keep waiting for tor
  if grep -q 'OLCRTC_EXIT_PROXY=' /etc/systemd/system/olcrtc-manager.service 2>/dev/null; then
    cp /etc/systemd/system/olcrtc-manager.service \
       "$TOR_BRIDGES_BACKUP_DIR/olcrtc-manager.service.bak.$(_now)"
    sed -i '/^After=.*tor@default/s|tor@default\.service||g; /^Wants=.*tor@default/s|tor@default\.service||g; /^Environment=OLCRTC_EXIT_PROXY=/d' \
      /etc/systemd/system/olcrtc-manager.service
    systemctl daemon-reload
    systemctl restart olcrtc-manager
  fi
  echo "[tor] OFF (bridges + torrc preserved; revert with: olc-feature tor on)"
}

# ---------- SPLIT (direct lists for olcrtc) ----------
split_on() {
  _save OLCRTC_ENABLE_SPLIT 1
  if [[ -x "$REPO_ROOT/scripts/setup-split-ru.sh" ]]; then
    OLCRTC_RU_VPS=1 bash "$REPO_ROOT/scripts/setup-split-ru.sh"
  fi
  systemctl restart olcrtc-manager 2>/dev/null || true
  echo "[split] ON"
}
split_off() {
  _save OLCRTC_ENABLE_SPLIT 0
  # Move split files out of the active dir so olcrtc stops using them.
  local d=/var/lib/olcrtc/lists
  if [[ -d "$d" ]]; then
    install -d "$d/disabled"
    mv "$d"/*.txt "$d/disabled/" 2>/dev/null || true
  fi
  systemctl restart olcrtc-manager 2>/dev/null || true
  echo "[split] OFF (lists moved to $d/disabled; revert with: olc-feature split on)"
}

# ---------- WEBTUNNEL ----------
webtunnel_on() {
  _save OLCRTC_ENABLE_WEBTUNNEL 1
  # shellcheck source=lib-webtunnel-build.sh
  source "$REPO_ROOT/scripts/lib-webtunnel-build.sh"
  if build_webtunnel_client log; then
    systemctl restart tor@default 2>/dev/null || true
    echo "[webtunnel] installed and active"
  else
    echo "[webtunnel] failed to install — Tor will use obfs4 only"
    return 1
  fi
}
webtunnel_off() {
  _save OLCRTC_ENABLE_WEBTUNNEL 0
  rm -f /usr/bin/webtunnel-client /usr/local/bin/webtunnel-client
  # Remove webtunnel lines from bridges.conf, keep obfs4
  if [[ -f "$TOR_BRIDGES" ]]; then
    cp "$TOR_BRIDGES" "$TOR_BRIDGES_BACKUP_DIR/bridges.conf.bak.$(_now)"
    sed -i '/^\s*Bridge webtunnel /d; /^\s*ClientTransportPlugin webtunnel /d' "$TOR_BRIDGES"
  fi
  systemctl restart tor@default 2>/dev/null || true
  echo "[webtunnel] OFF (obfs4-only)"
}

# ---------- BULK ----------
all_off() {
  zapret_off
  tor_off
  split_off
  echo "All toggles OFF — minimal test mode (manager keeps running, panel-only)"
}
all_on() {
  tor_on
  split_on
  zapret_on
  echo "All toggles ON — full RU VPS mode"
}

case "${1:-status}" in
  status|--status|-s) status ;;
  zapret) case "${2:-}" in
            on|enable) zapret_on ;;
            off|disable) zapret_off ;;
            reload) zapret_reload ;;
            *) echo "olc-feature zapret on|off|reload"; exit 1 ;;
          esac ;;
  tor)    case "${2:-}" in
            on|enable) tor_on ;;
            off|disable) tor_off ;;
            *) echo "olc-feature tor on|off"; exit 1 ;;
          esac ;;
  split)  case "${2:-}" in
            on|enable) split_on ;;
            off|disable) split_off ;;
            *) echo "olc-feature split on|off"; exit 1 ;;
          esac ;;
  webtunnel) case "${2:-}" in
            on|enable) webtunnel_on ;;
            off|disable) webtunnel_off ;;
            status) [[ -x /usr/bin/webtunnel-client ]] && echo present || echo missing ;;
            *) echo "olc-feature webtunnel on|off|status"; exit 1 ;;
          esac ;;
  all-off) all_off ;;
  all-on)  all_on ;;
  -h|--help) sed -n '3,18p' "$0" ;;
  *) echo "unknown: $1 (try: olc-feature --help)"; exit 1 ;;
esac
