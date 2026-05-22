#!/usr/bin/env bash
# Merge RU CIDR list + optional CDN/stream IPs for split tunnel (players via direct).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

RU="${RU_CIDRS:-/var/lib/olcrtc/ru-cidrs.txt}"
CDN="${CDN_CIDRS:-/var/lib/olcrtc/cdn-direct.txt}"
RU_PLAYER="${RU_PLAYER_CIDRS:-/var/lib/olcrtc/ru-player-cdn.txt}"
OUT="${OUT:-/var/lib/olcrtc/direct-all.txt}"
safety_check_output_path OUT "$OUT"

mkdir -p "$(dirname "$OUT")"
: >"$OUT"
[[ -f "$RU" ]] && grep -v '^#' "$RU" | awk 'NF' >>"$OUT"
[[ -f "$CDN" ]] && grep -v '^#' "$CDN" | awk 'NF' >>"$OUT"
[[ -f "$RU_PLAYER" ]] && grep -v '^#' "$RU_PLAYER" | awk 'NF' >>"$OUT"
awk '!seen[$0]++' "$OUT" >"${OUT}.tmp" && mv "${OUT}.tmp" "$OUT"
echo "merged $(wc -l <"$OUT") lines → $OUT"
