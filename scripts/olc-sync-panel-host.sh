#!/usr/bin/env bash
# Sync Jitsi/carrier hostnames from panel locations into direct-routing lists.
#
# Usage:
#   olc-sync-panel-host.sh add    <carrier> <room_id_or_url>
#   olc-sync-panel-host.sh remove <carrier> <room_id_or_url>
#   olc-sync-panel-host.sh sync-config   # rebuild from /etc/olcrtc-manager/config.json
#
# Hosts are stored in /var/lib/olcrtc/lists/panel-carrier-hosts.txt and merged
# into ru-direct-domains.txt so new panel rooms work with split/zapret without
# a full setup-split-ru run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PANEL_HOSTS=/var/lib/olcrtc/lists/panel-carrier-hosts.txt
DIRECT_LIST=/var/lib/olcrtc/ru-direct-domains.txt
CONFIG=/etc/olcrtc-manager/config.json

[[ "$(id -u)" -eq 0 ]] || { echo "root required" >&2; exit 1; }
install -d /var/lib/olcrtc/lists
touch "$PANEL_HOSTS"

host_from_room() {
  local raw="${1:-}"
  raw="${raw#https://}"
  raw="${raw#http://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  printf '%s' "$raw" | tr '[:upper:]' '[:lower:]'
}

merge_hosts() {
  [[ -f "$DIRECT_LIST" ]] || touch "$DIRECT_LIST"
  local h
  while IFS= read -r h || [[ -n "$h" ]]; do
    h="${h%%#*}"
    h="$(echo "$h" | xargs)"
    [[ -z "$h" ]] && continue
    if ! grep -qxF "$h" "$DIRECT_LIST" 2>/dev/null; then
      echo "$h" >>"$DIRECT_LIST"
      echo "[panel-host] added to direct list: $h"
    fi
  done <"$PANEL_HOSTS"
  if [[ -x "$REPO_ROOT/scripts/zapret-sync-excludes.sh" ]] \
    && [[ "${OLCRTC_ENABLE_ZAPRET:-1}" == "1" ]]; then
    bash "$REPO_ROOT/scripts/zapret-sync-excludes.sh" --reload-zapret 2>/dev/null \
      || bash "$REPO_ROOT/scripts/zapret-sync-excludes.sh" 2>/dev/null || true
  fi
}

add_host() {
  local h
  h="$(host_from_room "$2")"
  [[ -n "$h" ]] || return 0
  grep -qxF "$h" "$PANEL_HOSTS" 2>/dev/null || echo "$h" >>"$PANEL_HOSTS"
  merge_hosts
}

remove_host() {
  local h
  h="$(host_from_room "$2")"
  [[ -n "$h" ]] || return 0
  if [[ -f "$PANEL_HOSTS" ]]; then
    grep -vxF "$h" "$PANEL_HOSTS" >"${PANEL_HOSTS}.tmp" 2>/dev/null || true
    mv "${PANEL_HOSTS}.tmp" "$PANEL_HOSTS"
  fi
  if [[ -f "$DIRECT_LIST" ]]; then
    grep -vxF "$h" "$DIRECT_LIST" >"${DIRECT_LIST}.tmp" 2>/dev/null || true
    mv "${DIRECT_LIST}.tmp" "$DIRECT_LIST"
    echo "[panel-host] removed from direct list: $h"
  fi
  merge_hosts
}

sync_config() {
  : >"$PANEL_HOSTS"
  [[ -f "$CONFIG" ]] || { merge_hosts; return 0; }
  command -v jq >/dev/null || { echo "[panel-host] jq required for sync-config" >&2; return 1; }
  jq -r '.clients[]?.locations[]?.endpoint.room_id // empty' "$CONFIG" 2>/dev/null \
    | while read -r room; do
        h="$(host_from_room "$room")"
        [[ -n "$h" ]] && grep -qxF "$h" "$PANEL_HOSTS" 2>/dev/null || echo "$h" >>"$PANEL_HOSTS"
      done
  merge_hosts
  echo "[panel-host] sync-config done ($(wc -l <"$PANEL_HOSTS") hosts)"
}

case "${1:-}" in
  add)    add_host "$@" ;;
  remove) remove_host "$@" ;;
  sync-config) sync_config ;;
  *)
    echo "Usage: olc-sync-panel-host.sh add|remove <carrier> <room> | sync-config" >&2
    exit 1
    ;;
esac
