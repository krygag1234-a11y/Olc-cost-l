# Zapret / DPI на RU VPS

## Схема

```
Olcbox → VPS olcrtc → direct (*.ru + player CDN + ru-domains-extra)
                    → tor (force-tor + остальной мир)
VPS host (опционально) → zapret nfqws для direct HTTPS (blocked-tor + DPI)
```

## Установка из репозитория

На RU VPS при `agent-bootstrap.sh --full` / `--update` (если `OLCRTC_ENABLE_ZAPRET=1`, по умолчанию на RU):

```bash
sudo bash /opt/Olc-cost-l/scripts/install-zapret-vps.sh
```

| Режим | Условие |
|-------|---------|
| **minimal** | `data/zapret-olcrtc.config` + hostlist из `ru-blocked-tor-domains.txt` |
| **full** | `OLCRTC_ZAPRET_FULL=1` и `Z4R_SRC/config.default` (каталог zapret4rocket) |

Переменные:

| Переменная | Назначение |
|------------|------------|
| `OLCRTC_ENABLE_ZAPRET` | `0` — не ставить zapret |
| `OLCRTC_ZAPRET_FULL` | `1` — полный config zapret4rocket |
| `Z4R_SRC` | Путь к zapret4rocket (по умолчанию `data/zapret4rocket` в репо) |
| `Z4R_REPO_URL` | `git clone` если нет `config.default` локально |

Полный конфиг: скопируйте zapret4rocket в `data/zapret4rocket` или задайте `Z4R_SRC=/path/to/zapret4rocket`.

```bash
sudo OLCRTC_ZAPRET_FULL=1 Z4R_SRC=/path/to/zapret4rocket \
  bash /opt/Olc-cost-l/scripts/install-zapret-vps.sh
```

Hostlist (minimal): `scripts/sync-zapret-hostlist.sh` → `/var/lib/olcrtc/zapret-direct-hostlist.txt`.

**Не смешивать** с `OLCRTC_INCLUDE_CDN_IPS=1` (CDN /32 → 404 nginx).

## Без zapret

Split и Tor работают. Заблокированные `.ru` на direct без nfqws могут не открываться с VPS.

См. также [RU-BLOCKED-TOR.md](RU-BLOCKED-TOR.md), [SPLIT-ROUTING.md](SPLIT-ROUTING.md).
