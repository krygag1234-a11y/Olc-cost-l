#!/usr/bin/env bash
# Sync upstream olcrtc + olcrtc-manager, apply Olc-cost-l patches, queue manual review on failure.
#
# Usage:
#   upstream-sync.sh --check
#   upstream-sync.sh --apply [--no-build] [--zapret]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PINS_FILE="${UPSTREAM_PINS:-$REPO_ROOT/data/upstream-pins.json}"
REVIEW_DIR="${UPSTREAM_REVIEW_DIR:-/var/lib/olcrtc/upstream-review}"
OLCRTC_REPO="${OLCRTC_REPO:-/tmp/olcrtc-src}"
MGR_REPO="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}"

MODE=check
DO_BUILD=1
DO_ZAPRET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE=check ;;
    --apply) MODE=apply ;;
    --no-build) DO_BUILD=0 ;;
    --zapret) DO_ZAPRET=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
  shift
done

log() { echo "[upstream-sync] $*"; }

remote_sha() {
  curl -fsSL "https://api.github.com/repos/$1/commits/$2?per_page=1" | jq -r '.sha // empty' 2>/dev/null || true
}

pin_get() { jq -r --arg k "$1" --arg f "$2" '.[$k][$f] // empty' "$PINS_FILE" 2>/dev/null || true; }

pin_set() {
  local key="$1" sha="$2" ok="$3" now jok
  now="$(date -Iseconds)"
  [[ "$ok" == true || "$ok" == 1 ]] && jok=true || jok=false
  jq --arg sha "$sha" --arg now "$now" --argjson ok "$jok" \
    ".[\"$key\"].pinned_sha = \$sha | .[\"$key\"].last_sync = \$now | .[\"$key\"].last_apply_ok = \$ok" \
    "$PINS_FILE" >"${PINS_FILE}.tmp" && mv "${PINS_FILE}.tmp" "$PINS_FILE"
}

verify_markers() {
  local failed=0
  grep -q 'defaultMaxPayloadSize = 16\*1024 - 12' \
    "$OLCRTC_REPO/internal/transport/datachannel/transport.go" 2>/dev/null || {
    log "REVIEW: olcrtc 16K payload marker missing"
    failed=1
  }
  grep -q 'exitProxyReachable' "$MGR_REPO/cmd/olcrtc-manager/main.go" 2>/dev/null || {
    log "REVIEW: manager exitProxyReachable missing"
    failed=1
  }
  grep -q 'DirectDomainsFile\|direct_domains_file' "$MGR_REPO/cmd/olcrtc-manager/main.go" 2>/dev/null || {
    log "REVIEW: manager direct_domains_file missing"
    failed=1
  }
  grep -q 'defaultLocationLink\|OLCRTC_DEFAULT_LINK' "$MGR_REPO/cmd/olcrtc-manager/main.go" 2>/dev/null || true
  return "$failed"
}

check_status() {
  local osha msha orem mrem need=0 obranch mbranch
  obranch="$(pin_get olcrtc branch)"
  mbranch="$(pin_get olcrtc-manager branch)"
  [[ -n "$obranch" ]] || obranch="fix/all"
  [[ -n "$mbranch" ]] || mbranch="main"
  osha="$(remote_sha openlibrecommunity/olcrtc "$obranch")"
  msha="$(remote_sha BigDaddy3334/olcrtc-manager-panel "$mbranch")"
  orem="$(pin_get olcrtc pinned_sha)"
  mrem="$(pin_get olcrtc-manager pinned_sha)"
  log "olcrtc upstream ($obranch):  ${osha:0:12}  pinned: ${orem:-none}"
  log "manager upstream ($mbranch): ${msha:0:12}  pinned: ${mrem:-none}"
  [[ -n "$osha" && "$osha" != "$orem" ]] && { log "→ olcrtc: update available"; need=1; }
  [[ -n "$msha" && "$msha" != "$mrem" ]] && { log "→ manager: update available"; need=1; }
  [[ "$need" -eq 0 ]] && log "status: pins match upstream (or first run)"
  return "$need"
}

main() {
  [[ "$(id -u)" -eq 0 ]] || { echo "root required" >&2; exit 1; }
  command -v jq curl git go >/dev/null || { echo "need jq curl git go" >&2; exit 1; }
  [[ -f "$PINS_FILE" ]] || { echo "missing $PINS_FILE" >&2; exit 1; }
  mkdir -p "$REVIEW_DIR"

  if [[ "$MODE" == check ]]; then
    check_status || true
    "$SCRIPT_DIR/sync-zapret4rocket.sh" --check 2>/dev/null || true
    exit 0
  fi

  local logf="$REVIEW_DIR/apply-$(date +%Y%m%d-%H%M%S).log"
  if ! UPSTREAM_FRESH=1 BUILD="$DO_BUILD" OLC_REPO_ROOT="$REPO_ROOT" \
    bash "$SCRIPT_DIR/apply-olcrtc-patches.sh" >"$logf" 2>&1; then
    log "apply-olcrtc-patches FAILED — log: $logf"
    tail -30 "$logf" | while read -r l; do log "  $l"; done
  fi

  local osha msha failed=0
  osha="$(git -C "$OLCRTC_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  msha="$(git -C "$MGR_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"

  verify_markers || failed=1
  if [[ -s "$logf" ]] && grep -qiE 'FAILED|error:|fatal:' "$logf"; then
    failed=1
  fi

  pin_set olcrtc "$osha" $([[ "$failed" -eq 0 ]] && echo true || echo false)
  pin_set olcrtc-manager "$msha" $([[ "$failed" -eq 0 ]] && echo true || echo false)

  if [[ "$DO_ZAPRET" -eq 1 ]]; then
    "$SCRIPT_DIR/sync-zapret4rocket.sh" --apply || failed=1
  fi

  if [[ "$failed" -ne 0 ]]; then
    log "finished with REVIEW items — $logf and $REVIEW_DIR"
    exit 1
  fi

  if [[ "$DO_BUILD" -eq 1 ]]; then
    systemctl restart olcrtc-manager 2>/dev/null || true
  fi
  log "success olcrtc=${osha:0:12} manager=${msha:0:12}"
}

main "$@"
