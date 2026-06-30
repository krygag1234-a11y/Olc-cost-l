# [DEV] Синхронизация с upstream

> **Этот документ для разработчиков.** Пользователям он не нужен для установки и работы.

Olc-cost-l — **не форк**, а набор патчей поверх:

| Upstream | Ветка | Репозиторий |
|----------|-------|-------------|
| olcrtc | `master` | [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) |
| manager | `main` | [BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel) |
| manager stable | `stable-v1` | [krygag1234-a11y/local-panel-version](https://github.com/krygag1234-a11y/local-panel-version) |
| zapret4rocket | `master` | [IndeecFOX/zapret4rocket](https://github.com/IndeecFOX/zapret4rocket) |

Полностью автоматически «адаптировать любой коммит» без человека **нельзя** — upstream меняет структуру Go/TS, патчи ломаются. Скрипт делает **базовую** автоматизацию и складывает остальное в очередь на ручной разбор.

## Версии панели

- **Stable fork** (`--manager-stable`): Стабильный форк с проверенными патчами из https://github.com/krygag1234-a11y/local-panel-version
- **Latest** (`--manager-latest`): HEAD из upstream BigDaddy3334
- **Pinned** (по умолчанию): SHA из `upstream-pins.json`

При использовании `--manager-stable` скрипты автоматически клонируют из stable fork вместо upstream.

## Команды

```bash
# Проверить: есть ли новые коммиты upstream / zapret4rocket
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --check
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --check

# Подтянуть upstream, применить патчи, собрать бинарники
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --apply

# То же + обновить data/zapret4rocket (без смены /opt/zapret/config)
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --apply --zapret

# Только zapret4rocket assets + (опционально) config на VPS
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --apply
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --apply --config   # перезапишет /opt/zapret/config
```

## Что делает `upstream-sync.sh --apply`

1. `git fetch` + `reset --hard` клонов в `/tmp/olcrtc-src`, `/tmp/olcrtc-manager-panel`
2. По очереди: `.patch` + `patch-olcrtc-*.sh` / `patch-olcrtc-manager-*.sh` (см. [PATCHES.md](../patches/PATCHES.md))
3. `go build` → `/usr/local/bin/olcrtc`, `olcrtc-manager`
4. Запись SHA в `data/upstream-pins.json`
5. При ошибке шага — лог в `/var/lib/olcrtc/upstream-review/` и `last_apply_ok: false`

## Очередь ручной работы

Если патч не лёг:

```bash
ls -lt /var/lib/olcrtc/upstream-review/
```

Типичные действия:

1. Открыть upstream diff (`git -C /tmp/olcrtc-src log -1 -p`)
2. Обновить `.patch` или `patch-*.sh` в `patches/` / `scripts/`
3. Повторить `upstream-sync.sh --apply`

**Новые фичи upstream**, которых у нас нет (новые carrier, поля config) — осознанно переносятся в патчи; скрипт их не «понимает», только сообщает о падении.

## Версии (pins)

`data/upstream-pins.json` — последний успешно собранный SHA.  
`--check` сравнивает pins с GitHub API.

## zapret4rocket

| Что | Обновляется? |
|-----|----------------|
| bol-van **zapret** v72.12 (бинарники `/opt/zapret`) | только если нет бинарников (`install-zapret-vps.sh`) |
| **zapret4rocket** lists/config/strats | `sync-zapret4rocket.sh --apply` |
| `/opt/zapret/config` на VPS | **не** при обычном `--update`; только `--config` явно |

На VPS config мог быть установлен вручную (Zeefeer/strats) — перед `--config` сделайте бэкап.

## Ограничения (честно)

| Авто | Не авто |
|------|---------|
| pull upstream | рефакторинг upstream → правка патчей |
| известные patch/sh | новые файлы/поля без патча |
| сборка go | npm UI если сломался upstream |
| очередь review | решение «брать ли фичу upstream» |

Отдельная «нейронка на проекте» не обязательна: достаточно `--check` по cron + review-логов; сложные мержи — редко (раз в несколько недель).

## Cron (опционально)

```bash
# /etc/cron.d/olcrtc-upstream-check — только уведомление (exit 2 = есть обновления)
0 6 * * 1 root /opt/Olc-cost-l/scripts/upstream-sync.sh --check >>/var/log/olcrtc-upstream-check.log 2>&1
```

Авто `--apply` по cron **не рекомендуется** на проде без мониторинга review.
