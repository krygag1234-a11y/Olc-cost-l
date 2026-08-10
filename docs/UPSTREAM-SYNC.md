# [DEV] Синхронизация с upstream

> Этот документ для разработчиков. Production не собирает manager из upstream.

## Граница проектов

| Проект | Как используется |
|---|---|
| `openlibrecommunity/olcrtc` | закреплённый upstream core + отдельные core-патчи |
| `BigDaddy3334/olcrtc-manager-panel` | только покоммитный аудит |
| `components/olcrtc-manager` | единственный production-исходник нашей панели |
| `IndeecFOX/zapret4rocket` | отдельный аудит/обновление списков и стратегий |

`local-panel-version`, `manager-stable`, `manager-latest`, golden-panel и manager patch-stack
удалены из репозитория и production pipeline. `apply-olcrtc-patches.sh` патчит только OlcRTC core,
проверяет и копирует vendored manager во временный build-каталог, затем собирает бинарники.

## Аудит manager

Новый upstream-коммит классифицируется по таблице:

- взяли как есть;
- реализовали иначе/лучше;
- не нужен нашей архитектуре;
- конфликтует с нашими функциями;
- случайно потерян и должен быть возвращён.

После решения изменение вносится непосредственно в
`components/olcrtc-manager`, затем выполняются:

```bash
cd /opt/Olc-cost-l/components/olcrtc-manager
npm ci
npm run test:ui-backup
npm run build
go test ./...
cd /opt/Olc-cost-l
sudo OLC_ALLOW_VENDORED_BUILD_STATE=1 \
  scripts/verify-vendored-manager.sh components/olcrtc-manager
```

Семантический аудит миграции: [VENDORED-MANAGER-SEMANTIC-COMPARISON-20260803.md](VENDORED-MANAGER-SEMANTIC-COMPARISON-20260803.md).

## OlcRTC core

Core остаётся внешним проектом. Его pin хранится в `data/upstream-pins.json`, а
наши совместимые core-патчи применяются при bootstrap. Обновление pin выполняется
только после clean apply, Go-тестов и проверки manager/core вместе.

```bash
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --check
```

Старый `upstream-sync.sh --apply` затрагивает миграционный patch-stack и не
является production-командой обновления manager. Обычный VPS обновляется через
`upstream-sync.sh --apply` предназначен только для контролируемого обновления upstream core/pins.
Изменения upstream manager сначала проходят аудит и затем переносятся непосредственно в
`components/olcrtc-manager`. Обычный VPS обновляется через `olc-update`.

```bash
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --check
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --apply
```

Обычный update не должен перезаписывать пользовательский `/opt/zapret/config`.
Применение upstream-конфига допускается только отдельным явно выбранным режимом
после backup.
