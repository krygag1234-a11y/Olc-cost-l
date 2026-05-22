#!/usr/bin/env bash
# Merge geosite-ru + optional extras → ru-direct-domains.txt (used by olcrtc manager).
# NOTE: *.ru / .su / .рф are ALWAYS direct in olcrtc binary (builtin) — doktor-ktto-lordfilm.ru included.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${RU_DOMAINS:-/var/lib/olcrtc/ru-direct-domains.txt}"
safety_check_output_path OUT "$OUT"
GEOSITE="${GEOSITE_DOMAINS:-/var/lib/olcrtc/ru-geosite-domains.txt}"
EXTRA="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
EMBED="${RU_EMBED_BALANCERS:-$REPO_ROOT/data/ru-embed-balancers.txt}"
PLAYER="${RU_PLAYER_DOMAINS:-/var/lib/olcrtc/ru-player-cdn-domains.txt}"

bash "$SCRIPT_DIR/fetch-geosite-ru-domains.sh"
bash "$SCRIPT_DIR/fetch-player-cdn-domains.sh"

{
  echo "# Merged direct domain rules — $(date -Iseconds)"
  echo "# Builtin olcrtc: ALL hosts ending in .ru .su .рф (any mirror, e.g. doktor-ktto-lordfilm.ru)"
  [[ -f "$GEOSITE" ]] && grep -v '^#' "$GEOSITE" | awk 'NF'
  [[ -f "$EMBED" ]] && grep -v '^#' "$EMBED" | awk 'NF'
  [[ -f "$PLAYER" ]] && grep -v '^#' "$PLAYER" | awk 'NF'
  [[ -f "$EXTRA" ]] && grep -v '^#' "$EXTRA" | awk 'NF'
} | awk '!seen[$0]++' >"$OUT"

echo "merged $(grep -cvE '^#|^$' "$OUT" || echo 0) domain rules → $OUT"
