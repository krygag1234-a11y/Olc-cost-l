#!/usr/bin/env bash
# Merge RU CIDR list + optional CDN/stream IPs for split tunnel (players via direct).
set -euo pipefail

RU="${RU_CIDRS:-/var/lib/olcrtc/ru-cidrs.txt}"
CDN="${CDN_CIDRS:-/var/lib/olcrtc/cdn-direct.txt}"
OUT="${OUT:-/var/lib/olcrtc/direct-all.txt}"

mkdir -p "$(dirname "$OUT")"
: >"$OUT"
[[ -f "$RU" ]] && grep -v '^#' "$RU" | awk 'NF' >>"$OUT"
[[ -f "$CDN" ]] && grep -v '^#' "$CDN" | awk 'NF' >>"$OUT"
awk '!seen[$0]++' "$OUT" >"${OUT}.tmp" && mv "${OUT}.tmp" "$OUT"
echo "merged $(wc -l <"$OUT") lines → $OUT"
