#!/usr/bin/env bash
# Sync zapret4rocket assets from upstream (IndeecFOX/zapret4rocket).
#
# Usage:
#   sync-zapret4rocket.sh --check          # compare local vs GitHub master
#   sync-zapret4rocket.sh --apply          # git pull into Z4R_SRC
#   sync-zapret4rocket.sh --apply --config # also refresh /opt/zapret/config + restart
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

Z4R_REPO_URL="${Z4R_REPO_URL:-https://github.com/IndeecFOX/zapret4rocket.git}"
Z4R_BRANCH="${Z4R_BRANCH:-master}"
Z4R_SRC="${Z4R_SRC:-$REPO_ROOT/data/zapret4rocket}"
PINS_FILE="${UPSTREAM_PINS:-$REPO_ROOT/data/upstream-pins.json}"
APPLY=0
APPLY_CONFIG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) APPLY=0 ;;
    --apply) APPLY=1 ;;
    --config) APPLY_CONFIG=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
  shift
done

log() { echo "[sync-z4r] $*"; }

remote_sha() {
  curl -fsSL "https://api.github.com/repos/IndeecFOX/zapret4rocket/commits/${Z4R_BRANCH}?per_page=1" \
    | jq -r '.sha // empty' 2>/dev/null || true
}

local_sha() {
  [[ -d "$Z4R_SRC/.git" ]] || return 1
  git -C "$Z4R_SRC" rev-parse HEAD 2>/dev/null || true
}

refresh_tree() {
  if [[ -d "$Z4R_SRC/.git" ]]; then
    log "git pull $Z4R_SRC"
    git -C "$Z4R_SRC" fetch origin "$Z4R_BRANCH" --depth 1 2>/dev/null || \
      git -C "$Z4R_SRC" fetch origin "$Z4R_BRANCH"
    git -C "$Z4R_SRC" reset --hard "origin/$Z4R_BRANCH"
  else
    log "git clone → $Z4R_SRC"
    rm -rf "$Z4R_SRC"
    git clone -b "$Z4R_BRANCH" --depth 1 "$Z4R_REPO_URL" "$Z4R_SRC"
  fi
}

update_pin() {
  local sha="$1" ok="${2:-true}"
  command -v jq >/dev/null || return 0
  [[ -f "$PINS_FILE" ]] || return 0
  local now
  now="$(date -Iseconds)"
  jq --arg sha "$sha" --arg now "$now" --argjson ok "$ok" \
    '.zapret4rocket.pinned_sha = $sha | .zapret4rocket.last_sync = $now | .zapret4rocket.last_apply_ok = $ok' \
    "$PINS_FILE" >"${PINS_FILE}.tmp" && mv "${PINS_FILE}.tmp" "$PINS_FILE"
}

apply_zapret_config() {
  [[ -f "$Z4R_SRC/config.default" ]] || { log "no config.default in $Z4R_SRC"; return 1; }
  [[ -d /opt/zapret ]] || { log "/opt/zapret missing — run install-zapret-vps.sh first"; return 1; }
  safety_backup_file /opt/zapret/config 2>/dev/null || \
    cp -a /opt/zapret/config "/opt/zapret/config.bak.$(date +%s)" 2>/dev/null || true
  install -m 0644 "$Z4R_SRC/config.default" /opt/zapret/config
  mkdir -p /opt/zapret/lists /opt/zapret/ipset /opt/zapret/files/fake
  [[ -f "$Z4R_SRC/fake_files.tar.gz" ]] && tar -xzf "$Z4R_SRC/fake_files.tar.gz" -C /opt/zapret/files/fake 2>/dev/null || true
  [[ -d "$Z4R_SRC/lists" ]] && cp -a "$Z4R_SRC/lists/"* /opt/zapret/lists/ 2>/dev/null || true
  [[ -d "$Z4R_SRC/extra_strats" ]] && cp -a "$Z4R_SRC/extra_strats" /opt/zapret/
  if [[ -x /opt/zapret/init.d/sysv/zapret ]]; then
    timeout 120 /opt/zapret/init.d/sysv/zapret restart || systemctl restart zapret.service || true
  fi
  pidof nfqws >/dev/null && log "nfqws running" || log "WARN: nfqws not running after config apply"
}

main() {
  local rsha lsha
  rsha="$(remote_sha)"
  lsha="$(local_sha || true)"
  log "upstream $Z4R_BRANCH: ${rsha:0:12}"
  log "local Z4R_SRC:    ${lsha:-none}"
  if [[ -f /opt/zapret/config ]]; then
    log "installed config: $(wc -c </opt/zapret/config) bytes ($(head -1 /opt/zapret/config))"
  fi

  if [[ "$APPLY" -eq 0 ]]; then
    if [[ -n "$rsha" && "$rsha" == "$lsha" ]]; then
      log "status: up to date"
      exit 0
    fi
    log "status: update available"
    exit 2
  fi

  refresh_tree
  lsha="$(local_sha)"
  update_pin "$lsha" true
  if [[ "$APPLY_CONFIG" -eq 1 ]]; then
    apply_zapret_config || { update_pin "$lsha" false; exit 1; }
  fi
  log "done sha=${lsha:0:12}"
}

main "$@"
