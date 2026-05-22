#!/usr/bin/env bash
# Domains blocked in RF → route via Tor from RU VPS (override builtin *.ru direct).
# Sources: Refilter oref list + local seed. Not a full zapret replacement.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${RU_BLOCKED_TOR:-/var/lib/olcrtc/ru-blocked-tor-domains.txt}"
safety_check_output_path OUT "$OUT"
SEED="${RU_BLOCKED_TOR_SEED:-$REPO_ROOT/data/ru-blocked-tor-seed.txt}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() { echo "[blocked-tor] $*"; }

# Re:filter + antifilter community lists
REFILTER="${REFILTER_DOMAINS_URL:-https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst}"
ANTIFILTER="${ANTIFILTER_DOMAINS_URL:-https://community.antifilter.download/list/domains.lst}"
curl -fsSL --max-time 120 "$REFILTER" -o "$TMP/refilter.lst" 2>/dev/null || true
curl -fsSL --max-time 120 "$ANTIFILTER" -o "$TMP/antifilter.lst" 2>/dev/null || true

{
  echo "# Auto: RF-blocked → Tor override — $(date -Iseconds)"
  echo "# seed + refilter/antifilter (.ru/.su/.рф only → Tor on RU VPS)"
  [[ -f "$SEED" ]] && grep -v '^#' "$SEED" | awk 'NF'
  for lst in "$TMP/refilter.lst" "$TMP/antifilter.lst"; do
    [[ -f "$lst" ]] || continue
    while IFS= read -r d; do
      d="$(echo "$d" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
      [[ -z "$d" || "$d" == \#* ]] && continue
      case "$d" in
        *.ru|*.su|*.рф|*.xn--p1ai) echo "exact:${d}" ;;
      esac
    done <"$lst"
  done
} | awk '!seen[$0]++' >"$OUT"

n="$(grep -cvE '^#|^$' "$OUT" || echo 0)"
log "wrote ${n} rules → $OUT"
