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
| snowflake | `snowflake-client` (apt) | **не используем на VPS** — см. ниже |

### Snowflake (проверено на VPS, не работает)

Тест только snowflake (`Bridge snowflake 192.0.2.3:80`): bootstrap застрял на **10%**, `snowflake-client` падает с кодом **512** (~120 с). Вероятные причины: WebRTC/UDP на датацентре или нет доступных volunteer-proxy.

**В `bridges.conf` snowflake не добавляется.** Fallback включается только если создан маркер (после успешного ручного теста):

```bash
# только после того как вы сами убедились что snowflake bootstrap=100
sudo touch /var/lib/olcrtc/tor-snowflake-viable
```

Ручные мосты (капча, свои строки): `/var/lib/olcrtc/tor-user-bridges.txt` — подмешиваются при apply/rotate.

**IPv4:** на RU VPS часто режут IPv6-подсети провайдера Tor — `OLCRTC_BRIDGE_IPV4_ONLY=1` (по умолчанию). **Без IPv4 webtunnel** в пуле скрипт **не** заполняет `bridges.conf` IPv6 webtunnel — используется **obfs4-first** (см. `tor-bridge-lib.sh` → `pick_webtunnel_pool_lines`).

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
| `tor-bridge-deep-check.sh` | Раз в неделю (timer): **реальный** Tor bootstrap по ControlPort |

## Deep bootstrap check

Лёгкий аналог [TorBridgePulse](https://github.com/rzxas/TorBridgePulse): для каждого моста поднимается **временный** `tor`, опрос `GETINFO status/bootstrap-phase`, при 100% — проверка SOCKS через check.torproject.org. Результат пишется в `tor-bridge-health.tsv` (`bootstrap_ok` / `bootstrap_fail`); такие мосты получают бонус в score.

```bash
# вручную (топ по score из пула)
sudo /opt/Olc-cost-l/scripts/tor-bridge-deep-check.sh --from-pool --limit 8 --jobs 2

# один мост
sudo /opt/Olc-cost-l/scripts/tor-bridge-deep-check.sh --bridge 'Bridge webtunnel ...'

# timer (воскресенье 04:30)
systemctl status olcrtc-tor-bridge-deep.timer
```

Быстрый `probe_url` (TCP/HTTPS) остаётся для monitor/cron; deep check — тяжелее, не чаще раза в неделю.

## Переменные

```bash
BRIDGE_TYPES=webtunnel,obfs4    # или snowflake, vanilla
FETCH_MAX_AGE_SEC=14400
MAX_PROBE=72
MAX_POOL_LINES=500
FAST_WINDOW=6
TARGET_ACTIVE=12
OLCRTC_BRIDGE_IPV4_ONLY=1
OLCRTC_TOR_SNOWFLAKE_FALLBACK=0   # без /var/lib/olcrtc/tor-snowflake-viable не активен
BOOTSTRAP_TIMEOUT=90              # deep-check
```

## Что не тащим на VPS

- [1275.ru](https://1275.ru) — списки relay/exit, не мосты
- onionoo / Stem / симуляторы — мониторинг и исследования, не bootstrap
- Mix-Tor — экспериментальный PT

См. также [VPS-SETUP.md](VPS-SETUP.md), [SPLIT-ROUTING.md](SPLIT-ROUTING.md), [PERFORMANCE.md](PERFORMANCE.md) (потолок скорости, параллельные потоки).
