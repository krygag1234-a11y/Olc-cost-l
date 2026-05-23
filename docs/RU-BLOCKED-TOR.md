# Заблокированные в РФ сайты (в т.ч. `.ru`)

## Проблема

По умолчанию **любой `*.ru`** идёт **direct** с RU VPS. Если домен в реестре РКН / DPI, direct с дата-центра может не открыться без обхода на хосте.

## Решение в Olc-cost-l (RU VPS + zapret)

Файл **`/var/lib/olcrtc/ru-blocked-tor-domains.txt`** — хосты из реестров (Re-filter, antifilter, seed). На VPS с **zapret** olcrtc маршрутизирует их **direct**, а DPI обходит **nfqws** на исходящем HTTPS хоста.

| Переменная | Файл |
|------------|------|
| `OLCRTC_BLOCKED_TOR_DOMAINS` | `/var/lib/olcrtc/ru-blocked-tor-domains.txt` |

Обновление:

```bash
sudo bash /opt/Olc-cost-l/scripts/setup-split-ru.sh
sudo systemctl restart olcrtc-manager
```

Источники: `data/ru-blocked-tor-seed.txt` + [Re-filter](https://github.com/1andrevich/Re-filter-lists) + [antifilter](https://community.antifilter.download/list/domains.lst) (только `.ru`/`.su`/`.рф`).

В логах olcrtc: `route=direct` для таких хостов (не Tor exit).

Без zapret (`OLCRTC_ENABLE_ZAPRET=0`) те же домены остаются в списке, но DPI на direct может не пройти — нужен zapret или Tor на клиенте.

## Ограничения

- **Tor exit** для заблокированных `.ru` ломает плееры/CDN — поэтому не Tor, а direct+zapret.
- **Гео CDN** («недоступно в AT») — домены плеера → `ru-direct-domains.txt` / `data/ru-domains-extra.txt`.
- **Tor заблокирован** у клиента — мосты (`docs/TOR-BRIDGES.md`).

## Связь с плеерами

| Симптом | Что делать |
|---------|------------|
| AT / регион на embed | CDN в **direct** (player list, `ru-domains-extra.txt`) |
| Сайт .ru не открывается с VPS | В **blocked-tor** + zapret |
| Speedtest 2ip.ru, CDN `*.2ipcore.com` | `data/ru-domains-extra.txt` → direct |
