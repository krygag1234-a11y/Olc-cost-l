#!/usr/bin/env bash
# Domain-based split (geosite-style): RU TLD + streaming — без хрупких CDN /32 (404 nginx).
set -euo pipefail

OUT="${RU_DOMAINS:-/var/lib/olcrtc/ru-direct-domains.txt}"

cat >"$OUT" <<'EOF'
# RU direct by domain — VPS resolves CDN via RU DNS, no stale /32
# Ref: GrimbirdUsers/ru-routing-dat category-ru / streaming (2026)

# National TLD
.ru
.su
.рф
.xn--p1ai
.moscow

# Yandex / Mail / VK
.yandex.ru
.yandex.net
.yandex.com
.ya.ru
.yastatic.net
.strm.yandex.ru
.mail.ru
.vk.com
.vk.ru
.vkuser.net
.vk-portal.net
.vk-cdn.net
.userapi.com
.mycdn.me
.dzen.ru

# Streaming (2026 warnings: VPN off for playback)
.okko.tv
.okcdn.ru
.okko.sport
.ivi.ru
.ivi.tv
.ivicdn.tv
.kinopoisk.ru
.kpcdn.net
.rutube.ru
.rutube.net
.more.tv
.more-tv.ru
.premier.one
.start.ru
.start.film
.wink.ru
.megogo.net
.smotrim.ru
.kion.ru
.amediateka.ru
.viju.ru
.tvigle.ru
.boosty.ru
.cdnvideo.ru
.catcdn.ru

# Banks / market (often embedded)
.wildberries.ru
.wb.ru
.ozon.ru

# Telecom CDNs
.mts.ru
.beeline.ru
EOF

echo "wrote $(grep -cE '^[.]' "$OUT") domain suffix rules → $OUT"
