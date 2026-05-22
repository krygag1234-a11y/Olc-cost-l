#!/usr/bin/env bash
# Merge geosite-ru + optional extras → ru-direct-domains.txt (used by olcrtc manager).
# NOTE: *.ru / .su / .рф are ALWAYS direct in olcrtc binary (builtin) — doktor-ktto-lordfilm.ru included.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${RU_DOMAINS:-/var/lib/olcrtc/ru-direct-domains.txt}"
GEOSITE="${GEOSITE_DOMAINS:-/var/lib/olcrtc/ru-geosite-domains.txt}"
EXTRA="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"

bash "$SCRIPT_DIR/fetch-geosite-ru-domains.sh"

{
  echo "# Merged direct domain rules — $(date -Iseconds)"
  echo "# Builtin olcrtc: ALL hosts ending in .ru .su .рф (any mirror, e.g. doktor-ktto-lordfilm.ru)"
  [[ -f "$GEOSITE" ]] && grep -v '^#' "$GEOSITE" | awk 'NF'
  [[ -f "$EXTRA" ]] && grep -v '^#' "$EXTRA" | awk 'NF'
} | awk '!seen[$0]++' >"$OUT"

echo "merged $(grep -cvE '^#|^$' "$OUT" || echo 0) domain rules → $OUT"
