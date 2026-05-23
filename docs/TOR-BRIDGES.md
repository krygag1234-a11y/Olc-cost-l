# Tor bridge pool — как устроено и ускорение

## Источники пула

| URL | Содержимое |
|-----|------------|
| [igareck TOR_BRIDGES_ALL](https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/TOR-BRIDGES/TOR_BRIDGES_ALL.txt) | основной список |
| [Tor-Bridges-Collector](https://github.com/Delta-Kronecker/Tor-Bridges-Collector/tree/main/bridge) | `webtunnel_tested`, `obfs4_tested`, `*_72h`, `vanilla_tested` |

Список доп. URL: `data/bridge-extra-urls.txt` (или `BRIDGES_EXTRA_URLS` через запятую).

Обновить пул вручную:

```bash
sudo /opt/Olc-cost-l/scripts/fetch-bridge-extra-sources.sh
sudo systemctl restart tor@default
```

## Pluggable transports (RU VPS)

По умолчанию в пуле **webtunnel + obfs4** (`BRIDGE_TYPES=webtunnel,obfs4`). Установка бинарников:

```bash
sudo /opt/Olc-cost-l/scripts/install-tor-pluggable-transports.sh
```

| PT | Пакет / бинарник | Назначение |
|----|------------------|------------|
| webtunnel | `webtunnel-client` (сборка из gitlab.torproject.org) | основной обход DPI |
| obfs4 | `obfs4proxy` (apt) | запасной PT ([форум Tor](https://forum.torproject.org/t/tor/21439/9)) |
| snowflake | `snowflake-client` (apt) | опциональный fallback через WebRTC |

**Snowflake fallback** (одна строка `Bridge snowflake 192.0.2.3:80` + CTP):

```bash
# /etc/olcrtc-manager/panel.env или export перед pool/rotate
OLCRTC_TOR_SNOWFLAKE_FALLBACK=1
```

Ручные мосты (капча, свои строки): `/var/lib/olcrtc/tor-user-bridges.txt` — подмешиваются при apply/rotate.

**IPv4:** на RU VPS часто режут IPv6-подсети провайдера Tor — `OLCRTC_BRIDGE_IPV4_ONLY=1` (по умолчанию) понижает приоритет IPv6-мостов в выборе.

## Healthcheck (важно)

Cron `healthcheck.sh` проверяет панель по **`/admin`** (не `/` — иначе 404 и ложный рестарт Tor каждые 10 мин).

Tor восстанавливается только если SOCKS реально мёртв; панель без Tor — только `restart olcrtc-manager`.

## Память

Скрипт **не держит весь список в RAM постоянно**. Один раз скачивает текст, парсит построчно, пишет в `/var/lib/olcrtc/tor-bridges-pool.txt` (обрезка до **500** строк по score). Health — TSV `/var/lib/olcrtc/tor-bridge-health.tsv`.

## Режимы

| Команда | Когда |
|---------|--------|
| `tor-bridge-pool.sh --fetch --url-only` | Скачать (если pool старше 4ч), probe до **72** мостов, apply |
| `tor-bridge-monitor.sh` | Каждые 10–20 мин: Tor OK → лёгкий probe; Tor down → fast rotate (3 провала) |
| `tor-bridge-rotate.sh` | Сдвиг окна мостов **без** скачивания |
| `healthcheck.sh` | Cron */10: rotate/apply только если Tor мёртв |

## Переменные

```bash
BRIDGE_TYPES=webtunnel,obfs4    # или snowflake, vanilla
FETCH_MAX_AGE_SEC=14400
MAX_PROBE=72
MAX_POOL_LINES=500
FAST_WINDOW=6
TARGET_ACTIVE=12
OLCRTC_BRIDGE_IPV4_ONLY=1
OLCRTC_TOR_SNOWFLAKE_FALLBACK=0
```

## Что не тащим на VPS

- [1275.ru](https://1275.ru) — списки relay/exit, не мосты
- onionoo / Stem / симуляторы — мониторинг и исследования, не bootstrap
- Mix-Tor — экспериментальный PT

См. также [VPS-SETUP.md](VPS-SETUP.md), [SPLIT-ROUTING.md](SPLIT-ROUTING.md).
