# Заблокированные в РФ сайты (в т.ч. `.ru`)

## Проблема

По умолчанию **любой `*.ru`** идёт **direct** с RU VPS. Если домен в реестре РКН / DPI, direct с дата-центра всё равно может не открыться.

## Решение в Olc-cost-l (простое)

Файл **`/var/lib/olcrtc/ru-blocked-tor-domains.txt`** — список хостов, для которых olcrtc **принудительно использует Tor**, даже если это `.ru`.

| Переменная | Файл |
|------------|------|
| `OLCRTC_BLOCKED_TOR_DOMAINS` | `/var/lib/olcrtc/ru-blocked-tor-domains.txt` |

Обновление:

```bash
sudo bash /opt/Olc-cost-l/scripts/fetch-ru-blocked-tor-domains.sh
sudo systemctl restart olcrtc-manager
```

Источники: `data/ru-blocked-tor-seed.txt` + [Re-filter domains_all.lst](https://github.com/1andrevich/Re-filter-lists) + [antifilter domains.lst](https://community.antifilter.download/list/domains.lst) (только `.ru`/`.su`/`.рф`).

В логах: `route=tor` для таких хостов.

## Ограничения

- **Tor заблокирован** на стороне клиента/провайдера — нужны мосты (`docs/TOR-BRIDGES.md`), список blocked-tor не поможет.
- **Гео CDN** («недоступно в AT») — это **плеерные** домены → они в `ru-direct-domains.txt` / `ru-video-balancers-full.txt`, нужен **direct**, не Tor.
- DPI на **весь** HTTPS без списка доменов — см. zapret ниже.

## Связь с плеерами

| Симптом | Что делать |
|---------|------------|
| AT / регион на embed | Добавить CDN в **direct** (player list) |
| Сайт .ru не открывается с VPS | Добавить в **blocked-tor** |
