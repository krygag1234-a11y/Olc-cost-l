#!/usr/bin/env bash
# Safety helpers — refuse writes outside known OlcRTC paths.
[[ -n "${_OLC_SAFETY_LOADED:-}" ]] && return 0
_OLC_SAFETY_LOADED=1

# Paths scripts may create/modify (never /etc/ssh, never iptables, never full torrc wipe)
OLC_ALLOWED_WRITE_PREFIXES=(
  /etc/olcrtc-manager
  /etc/tor/bridges.conf
  /etc/tor/torrc
  /etc/tor/torrc.d
  /etc/apparmor.d/local/system_tor
  /etc/systemd/system/olcrtc-
  /etc/cron.d/olcrtc-healthcheck
  /etc/sysctl.d/99-olcrtc-performance.conf
  /var/lib/olcrtc
  /var/log/olcrtc-
  /usr/local/bin/olcrtc
  /usr/local/bin/olcrtc-manager
  /usr/bin/webtunnel-client
)

# panel.env keys setup-split-ru may create/update (never touch unrelated vars)
OLC_PANEL_ENV_KEYS=(
  OLCRTC_DIRECT_CIDRS
  OLCRTC_DIRECT_DOMAINS
  OLCRTC_BLOCKED_TOR_DOMAINS
)

safety_require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "ERROR: root required" >&2; return 1; }
}

safety_path_allowed() {
  local path="$1"
  local real
  real="$(readlink -f "$path" 2>/dev/null || echo "$path")"
  [[ "$real" == "/" ]] && return 1
  for prefix in "${OLC_ALLOWED_WRITE_PREFIXES[@]}"; do
    [[ "$real" == "$prefix" || "$real" == "$prefix"* ]] && return 0
  done
  return 1
}

# Refuse OUT=/etc/passwd style mistakes from env
safety_check_output_path() {
  local label="$1" path="$2"
  [[ -n "$path" ]] || { echo "REFUSE empty $label" >&2; return 1; }
  [[ "$path" == /* ]] || { echo "REFUSE $label must be absolute: $path" >&2; return 1; }
  safety_path_allowed "$path" || {
    echo "REFUSE $label outside allowlist: $path" >&2
    return 1
  }
}

safety_check_install_dir() {
  local dir="$1"
  local real
  real="$(readlink -f "$dir" 2>/dev/null || echo "$dir")"
  case "$real" in
    /|/etc|/etc/*|/usr|/usr/*|/bin|/sbin|/lib|/lib/*|/boot|/root)
      echo "REFUSE unsafe OLC_INSTALL_DIR: $dir" >&2
      return 1
      ;;
  esac
  return 0
}

safety_validate_git_build_dir() {
  local dir="$1" label="$2"
  local real
  real="$(readlink -f "$dir" 2>/dev/null || echo "$dir")"
  [[ "$real" == /tmp/* || "$real" == /var/tmp/* ]] || {
    echo "REFUSE $label=$dir (git build dirs must be under /tmp or /var/tmp)" >&2
    return 1
  }
}

safety_ensure_olcrtc_symlink() {
  local target="$1"
  local real_target
  real_target="$(readlink -f "$target" 2>/dev/null || echo "$target")"
  if [[ -e /opt/olcrtc && ! -L /opt/olcrtc ]]; then
    echo "REFUSE: /opt/olcrtc exists and is not a symlink (move/rename manually first)" >&2
    return 1
  fi
  ln -sfn "$real_target" /opt/olcrtc
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
  safety_path_allowed "$f" || return 1
  [[ -f "$f" ]] || return 0
  cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
}

# Append only; never truncate whole /etc/tor/torrc
safety_torrc_include_bridges() {
  local torrc="${1:-/etc/tor/torrc}"
  safety_path_allowed "$torrc" || return 1
  safety_backup_file "$torrc"
  grep -q '%include /etc/tor/bridges.conf' "$torrc" 2>/dev/null || \
    echo '%include /etc/tor/bridges.conf' >>"$torrc"
}

# Tor SOCKS only on localhost (append block once)
safety_torrc_local_socks_only() {
  local torrc="${1:-/etc/tor/torrc}"
  local mark="# olcrtc: local socks only"
  safety_path_allowed "$torrc" || return 1
  grep -qF "$mark" "$torrc" 2>/dev/null && return 0
  safety_backup_file "$torrc"
  cat >>"$torrc" <<EOF

$mark
SocksPolicy accept 127.0.0.1/32
SocksPolicy accept ::1/128
SocksPolicy reject *
EOF
}

safety_panel_env_set() {
  local env_file="$1" key="$2" val="$3"
  local ok=0 k
  safety_path_allowed "$env_file" || return 1
  for k in "${OLC_PANEL_ENV_KEYS[@]}"; do
    [[ "$key" == "$k" ]] && ok=1 && break
  done
  [[ "$ok" -eq 1 ]] || {
    echo "REFUSE panel.env key not whitelisted: $key" >&2
    return 1
  }
  mkdir -p "$(dirname "$env_file")"
  touch "$env_file"
  if grep -q "^${key}=" "$env_file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$env_file"
  else
    echo "${key}=${val}" >>"$env_file"
  fi
}
