#!/usr/bin/env bash
# Extract hostnames from a page/HTML (for finding player CDN) → append to ru-domains-extra.txt
# Usage: discover-page-hosts.sh 'https://doktor-ktto-lordfilm.ru/14-sezon-1-seriya/'
set -euo pipefail

URL="${1:-}"
[[ -n "$URL" ]] || { echo "usage: $0 <url>" >&2; exit 1; }

OUT="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

curl -fsSL -A 'Mozilla/5.0' --max-time 25 "$URL" >"$TMP" || exit 1

{
  grep -oiE '[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+' "$TMP" || true
  grep -oiE 'https?://[^/\"'\''<> ]+' "$TMP" | sed 's|https\?://||;s|/.*||' || true
} | tr '[:upper:]' '[:lower:]' | sort -u | while read -r h; do
  [[ -z "$h" ]] && continue
  [[ "$h" == *.* ]] || continue
  echo "suffix:.${h}"
  echo "exact:${h}"
done | awk '!seen[$0]++' >>"$OUT"

echo "appended hosts from $URL → $OUT (review file)"
