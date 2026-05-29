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
PANEL_CIDRS=/var/lib/olcrtc/lists/panel-carrier-cidrs.txt
DIRECT_LIST=/var/lib/olcrtc/ru-direct-domains.txt
CIDR_LIST=/var/lib/olcrtc/ru-cidrs.txt
CONFIG=/etc/olcrtc-manager/config.json
SEED_DOMAINS="$REPO_ROOT/data/panel-carrier-domain-seed.txt"
SEED_CIDRS="$REPO_ROOT/data/panel-carrier-ip-seed.txt"
ANALYZER="$REPO_ROOT/scripts/olc-split-analyze.sh"

[[ "$(id -u)" -eq 0 ]] || { echo "root required" >&2; exit 1; }
install -d /var/lib/olcrtc/lists
touch "$PANEL_HOSTS"
touch "$PANEL_CIDRS"

host_from_room() {
  local raw="${1:-}"
  raw="${raw#https://}"
  raw="${raw#http://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  printf '%s' "$raw" | tr '[:upper:]' '[:lower:]'
}

is_ipv4() {
  local s="${1:-}"
  [[ "$s" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=.
  local a b c d
  read -r a b c d <<<"$s"
  for n in "$a" "$b" "$c" "$d"; do
    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    (( n >= 0 && n <= 255 )) || return 1
  done
  return 0
}

merge_hosts() {
  if [[ -x "$ANALYZER" ]]; then
    bash "$ANALYZER" rebuild >/dev/null 2>&1 || true
    if [[ "${OLC_SKIP_ZAPRET_SYNC:-0}" != "1" ]] \
      && [[ -x "$REPO_ROOT/scripts/zapret-sync-excludes.sh" ]] \
      && [[ "${OLCRTC_ENABLE_ZAPRET:-1}" == "1" ]]; then
      bash "$REPO_ROOT/scripts/zapret-sync-excludes.sh" --reload-zapret 2>/dev/null \
        || bash "$REPO_ROOT/scripts/zapret-sync-excludes.sh" 2>/dev/null || true
    fi
    return 0
  fi
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
  if [[ -f "$SEED_DOMAINS" ]]; then
    while IFS= read -r h || [[ -n "$h" ]]; do
      h="${h%%#*}"
      h="$(echo "$h" | xargs)"
      [[ -z "$h" ]] && continue
      if ! grep -qxF "$h" "$DIRECT_LIST" 2>/dev/null; then
        echo "$h" >>"$DIRECT_LIST"
        echo "[panel-host] added seed domain: $h"
      fi
    done <"$SEED_DOMAINS"
  fi

  [[ -f "$CIDR_LIST" ]] || touch "$CIDR_LIST"
  local c
  while IFS= read -r c || [[ -n "$c" ]]; do
    c="${c%%#*}"
    c="$(echo "$c" | xargs)"
    [[ -z "$c" ]] && continue
    if ! grep -qxF "$c" "$CIDR_LIST" 2>/dev/null; then
      echo "$c" >>"$CIDR_LIST"
      echo "[panel-host] added to cidr list: $c"
    fi
  done <"$PANEL_CIDRS"

  if [[ -f "$SEED_CIDRS" ]]; then
    while IFS= read -r c || [[ -n "$c" ]]; do
      c="${c%%#*}"
      c="$(echo "$c" | xargs)"
      [[ -z "$c" ]] && continue
      if ! grep -qxF "$c" "$CIDR_LIST" 2>/dev/null; then
        echo "$c" >>"$CIDR_LIST"
        echo "[panel-host] added seed cidr: $c"
      fi
    done <"$SEED_CIDRS"
  fi

  if [[ "${OLC_SKIP_ZAPRET_SYNC:-0}" == "1" ]]; then
    return 0
  fi
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
  if is_ipv4 "$h"; then
    local cidr="${h}/32"
    grep -qxF "$cidr" "$PANEL_CIDRS" 2>/dev/null || echo "$cidr" >>"$PANEL_CIDRS"
  else
    grep -qxF "$h" "$PANEL_HOSTS" 2>/dev/null || echo "$h" >>"$PANEL_HOSTS"
  fi
  merge_hosts
}

remove_host() {
  local h
  h="$(host_from_room "$2")"
  [[ -n "$h" ]] || return 0
  if is_ipv4 "$h"; then
    local cidr="${h}/32"
    if [[ -f "$PANEL_CIDRS" ]]; then
      grep -vxF "$cidr" "$PANEL_CIDRS" >"${PANEL_CIDRS}.tmp" 2>/dev/null || true
      mv "${PANEL_CIDRS}.tmp" "$PANEL_CIDRS"
    fi
    if [[ -f "$CIDR_LIST" ]]; then
      grep -vxF "$cidr" "$CIDR_LIST" >"${CIDR_LIST}.tmp" 2>/dev/null || true
      mv "${CIDR_LIST}.tmp" "$CIDR_LIST"
      echo "[panel-host] removed from cidr list: $cidr"
    fi
  else
    if [[ -f "$PANEL_HOSTS" ]]; then
      grep -vxF "$h" "$PANEL_HOSTS" >"${PANEL_HOSTS}.tmp" 2>/dev/null || true
      mv "${PANEL_HOSTS}.tmp" "$PANEL_HOSTS"
    fi
    if [[ -f "$DIRECT_LIST" ]]; then
      grep -vxF "$h" "$DIRECT_LIST" >"${DIRECT_LIST}.tmp" 2>/dev/null || true
      mv "${DIRECT_LIST}.tmp" "$DIRECT_LIST"
      echo "[panel-host] removed from direct list: $h"
    fi
  fi
  OLC_SKIP_ZAPRET_SYNC=1 merge_hosts
}

sync_config() {
  if [[ -x "$ANALYZER" ]]; then
    bash "$ANALYZER" sync-config "$CONFIG"
    return $?
  fi
  : >"$PANEL_HOSTS"
  : >"$PANEL_CIDRS"
  [[ -f "$CONFIG" ]] || { merge_hosts; return 0; }
  command -v jq >/dev/null || { echo "[panel-host] jq required for sync-config" >&2; return 1; }
  jq -r '.clients[]?.locations[]?.endpoint.room_id // empty' "$CONFIG" 2>/dev/null \
    | while read -r room; do
        h="$(host_from_room "$room")"
        [[ -n "$h" ]] || continue
        if is_ipv4 "$h"; then
          cidr="${h}/32"
          grep -qxF "$cidr" "$PANEL_CIDRS" 2>/dev/null || echo "$cidr" >>"$PANEL_CIDRS"
        else
          grep -qxF "$h" "$PANEL_HOSTS" 2>/dev/null || echo "$h" >>"$PANEL_HOSTS"
        fi
      done
  merge_hosts
  echo "[panel-host] sync-config done ($(wc -l <"$PANEL_HOSTS") hosts, $(wc -l <"$PANEL_CIDRS") cidrs)"
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
