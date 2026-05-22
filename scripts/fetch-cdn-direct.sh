#!/usr/bin/env bash
# Resolve common video/CDN hostnames → /32 for olcrtc direct_cidrs (fix white nginx player via Tor).
set -euo pipefail

OUT="${CDN_CIDRS:-/var/lib/olcrtc/cdn-direct.txt}"
HOSTS=(
  youtube.com www.youtube.com googlevideo.com ytimg.com
  vimeo.com player.vimeo.com
  rutube.ru static.rutube.ru
  vk.com vkvideo.ru
  dzen.ru
  twitch.tv static-cdn.jtvnw.net
  netflix.com nflxvideo.net
)

mkdir -p "$(dirname "$OUT")"
{
  echo "# CDN/stream direct — $(date -Iseconds)"
  echo "# Regenerate: fetch-cdn-direct.sh && merge-direct-cidrs.sh"
  for h in "${HOSTS[@]}"; do
    getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u | while read -r ip; do
      echo "${ip}/32  # $h"
    done
  done
} | awk '!seen[$1]++' >"$OUT"
echo "wrote $(grep -c '/32' "$OUT" || echo 0) entries → $OUT"
