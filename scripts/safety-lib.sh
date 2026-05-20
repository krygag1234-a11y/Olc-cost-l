#!/usr/bin/env bash
# Safety helpers — only allow writes under known paths.
[[ -n "${_OLC_SAFETY_LOADED:-}" ]] && return 0
_OLC_SAFETY_LOADED=1

# Paths scripts may create/modify (never /etc/ssh, never full torrc wipe)
OLC_ALLOWED_WRITE_PREFIXES=(
  /etc/olcrtc-manager
  /etc/tor/bridges.conf
  /etc/tor/torrc.d
  /etc/apparmor.d/local/system_tor
  /etc/systemd/system/olcrtc-
  /etc/sysctl.d/99-olcrtc-performance.conf
  /var/lib/olcrtc
  /var/log/olcrtc-
  /usr/local/bin/olcrtc
  /usr/local/bin/olcrtc-manager
  /usr/bin/webtunnel-client
)

safety_require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "ERROR: root required" >&2; return 1; }
}

safety_path_allowed() {
  local path="$1"
  local real
  real="$(readlink -f "$path" 2>/dev/null || echo "$path")"
  for prefix in "${OLC_ALLOWED_WRITE_PREFIXES[@]}"; do
    [[ "$real" == "$prefix" || "$real" == "$prefix"* ]] && return 0
  done
  return 1
}

safety_install_file() {
  local src="$1" dest="$2" mode="${3:-0644}"
  safety_path_allowed "$dest" || {
    echo "REFUSE write outside allowlist: $dest" >&2
    return 1
  }
  if [[ -f "$dest" ]]; then
    cp -a "$dest" "${dest}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi
  install -m "$mode" "$src" "$dest"
}

safety_backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
}

# Append to torrc only; never truncate whole /etc/tor/torrc
safety_torrc_include_bridges() {
  local torrc="${1:-/etc/tor/torrc}"
  grep -q '%include /etc/tor/bridges.conf' "$torrc" 2>/dev/null || \
    echo '%include /etc/tor/bridges.conf' >>"$torrc"
}
