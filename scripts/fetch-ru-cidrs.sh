#!/usr/bin/env bash
# Download Russian IPv4 CIDR list for split routing (direct vs Tor).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

OUT="${OUT:-/var/lib/olcrtc/ru-cidrs.txt}"
safety_check_output_path OUT "$OUT"
URL="${URL:-https://www.ipdeny.com/ipblocks/data/countries/ru.zone}"

mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp)"
curl -fsSL --max-time 60 "$URL" -o "$tmp"
# normalize: one CIDR per line
awk 'NF && $0 !~ /^#/ {print}' "$tmp" | sort -u >"${tmp}.sorted"
{
  echo "# Russian IPv4 CIDRs — $(date -Iseconds)"
  echo "# source: $URL"
  cat "${tmp}.sorted"
} >"$OUT"
rm -f "$tmp" "${tmp}.sorted"
echo "wrote $(wc -l <"$OUT") lines to $OUT"
