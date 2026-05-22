#!/usr/bin/env bash
# RU streaming/CDN hosts → /32 for split tunnel (плеер «недоступно в регионе» при Tor exit).
# Только для RU VPS (вызывается из setup-split-ru.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

OUT="${RU_PLAYER_CIDRS:-/var/lib/olcrtc/ru-player-cdn.txt}"
safety_check_output_path OUT "$OUT"

# Домены CDN/API российских площадок (дополняйте под свои сайты)
HOSTS=(
  okko.tv okcdn.ru okko.sport
  ivi.ru ivicdn.tv ivi.tv
  kinopoisk.ru widgets.kinopoisk.ru st.kp.yandex.net
  rutube.ru pic.rutube.ru static.rutube.ru
  vk.com vk.ru vkuser.net vk-portal.net userapi.com
  dzen.ru strm.yandex.ru yastatic.net
  more.tv more-tv.ru
  premier.one
  start.ru start.film
  wink.ru winknews.ru
  megogo.net
  smotrim.ru vgtrk.com
  cdnvideo.ru catcdn.ru
  boosty.to
  kion.ru
  viju.ru
  amediateka.ru
  tvigle.ru
  pladform.ru
  youtube.com www.youtube.com googlevideo.com ytimg.com
  vimeo.com player.vimeo.com
  twitch.tv static-cdn.jtvnw.net
)

mkdir -p "$(dirname "$OUT")"
{
  echo "# RU/player CDN direct — $(date -Iseconds)"
  echo "# Regenerate: setup-split-ru.sh"
  for h in "${HOSTS[@]}"; do
    getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u | while read -r ip; do
      echo "${ip}/32  # ${h}"
    done
  done
} | awk '!seen[$1]++' >"$OUT"
echo "ru-player-cdn: $(grep -c '/32' "$OUT" || echo 0) entries → $OUT"
