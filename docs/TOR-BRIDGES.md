# Tor bridge pool — как устроено и ускорение

Источник: [TOR_BRIDGES_ALL.txt](https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/TOR-BRIDGES/TOR_BRIDGES_ALL.txt) (igareck).

## Память

Скрипт **не держит весь список в RAM постоянно**. Один раз скачивает текст (~сотни KB–несколько MB), парсит построчно, пишет в `/var/lib/olcrtc/tor-bridges-pool.txt` (обрезка до **500** строк по score). Health — TSV `/var/lib/olcrtc/tor-bridge-health.tsv`.

## Режимы

| Команда | Когда |
|---------|--------|
| `tor-bridge-pool.sh --fetch --url-only` | Полный цикл: скачать (если pool старше 4ч), probe до **72** мостов, apply |
| `tor-bridge-monitor.sh` | Каждые 10–20 мин: Tor OK → лёгкий probe; Tor down → **fast rotate** |
| `tor-bridge-rotate.sh` | Сдвиг окна мостов **без** скачивания (секунды) |
| `healthcheck.sh` | Cron: сначала rotate, потом apply только если Tor мёртв |

## Переменные

```bash
FETCH_MAX_AGE_SEC=14400   # не качать чаще 4ч
MAX_PROBE=72              # параллельных проверок за раз
MAX_POOL_LINES=500
FAST_WINDOW=6             # мостов при быстрой ротации
PARALLEL_JOBS=6
TARGET_ACTIVE=12
```

## Почему раньше было долго

1. Каждый раз качался весь TXT и пробились **все** строки pool.
2. `systemctl restart tor` + ожидание bootstrap до **80s**.
3. Monitor только обновлял health, без fast rotate при обрыве.

Сейчас: кэш pool, probe топ-N, `tor-bridges-good.txt`, rotate за секунды.

## Плееры (белый экран / «недоступно в регионе»)

**Только RU VPS.** Один скрипт:

```bash
sudo /opt/Olc-cost-l/scripts/setup-split-ru.sh
sudo systemctl restart olcrtc-manager
```

Включает RU CIDR + global CDN + **RU player CDN** (Okko, IVI, Rutube, …).  
См. [RU-VPS-ONLY.md](RU-VPS-ONLY.md), [SECURITY-NETWORK.md](SECURITY-NETWORK.md).
