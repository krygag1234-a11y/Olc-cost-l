# Zapret / DPI на RU VPS

## Схема

```
Olcbox → VPS olcrtc → direct (*.ru + player CDN + ru-domains-extra)
                    → tor (force-tor + остальной мир)
VPS host (опционально) → zapret nfqws для direct HTTPS (blocked-tor + DPI)
```

## Исключения (RU whitelist + carriers)

```bash
sudo bash /opt/Olc-cost-l/scripts/zapret-sync-excludes.sh --reload-zapret
sudo bash /opt/Olc-cost-l/scripts/fetch-zapret-community-excludes.sh  # Flowseal lists
```

См. [PROJECT-STATE.md](PROJECT-STATE.md).

## Установка

```bash
sudo bash /opt/Olc-cost-l/scripts/install-zapret-vps.sh
```

| Режим | Условие |
|-------|---------|
| **minimal** | `data/zapret-olcrtc.config` + hostlist |
| **full** | `OLCRTC_ZAPRET_FULL=1` + `data/zapret4rocket/config.default` |

## Обновление zapret4rocket

Upstream: [IndeecFOX/zapret4rocket](https://github.com/IndeecFOX/zapret4rocket)

```bash
# Проверить новый коммит на GitHub vs data/zapret4rocket
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --check

# Скачать lists/strats/config.default в репо (data/zapret4rocket)
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --apply

# Ещё и перезаписать /opt/zapret/config + restart (осторожно, есть бэкап)
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --apply --config
```

**Важно:** `agent-bootstrap.sh --update` **не** перезаписывает `/opt/zapret/config`, если zapret уже установлен. Бинарники bol-van zapret v72.12 тоже не обновляются повторно — только при отсутствии `/opt/zapret/nfq/nfqws`.

При `install-zapret-vps.sh` по умолчанию клонируется `https://github.com/IndeecFOX/zapret4rocket.git` в `data/zapret4rocket`.

| Переменная | Назначение |
|------------|------------|
| `OLCRTC_ENABLE_ZAPRET` | `0` — не ставить |
| `OLCRTC_ZAPRET_FULL` | `1` — config.default zapret4rocket |
| `Z4R_SRC` | каталог assets (default: `data/zapret4rocket`) |
| `Z4R_REPO_URL` | git URL (default: IndeecFOX) |
| `OLCRTC_ZAPRET_SYNC` | `0` — не pull z4r в install |

Hostlist (minimal): `scripts/sync-zapret-hostlist.sh`.

См. [UPSTREAM-SYNC.md](UPSTREAM-SYNC.md), [RU-BLOCKED-TOR.md](RU-BLOCKED-TOR.md).
