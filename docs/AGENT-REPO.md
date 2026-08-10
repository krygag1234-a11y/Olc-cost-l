# [DEV] Карта репозитория для агентов

**Актуально для vendored-pipeline с 2026-08-10.** Старые инструкции про
`local-panel-version`, golden-panel и наложение manager patch-stack удалены.

## Источники истины

| Область | Источник |
|---|---|
| Manager frontend/backend | `components/olcrtc-manager` |
| Установка и переход install→update | `install.sh` |
| Сборка/модули/TUI | `scripts/agent-bootstrap.sh` |
| Оркестрация core patches + vendored manager build | `scripts/apply-olcrtc-patches.sh` |
| Обновление установленного VPS | `scripts/olc-update.sh` |
| Backup/import | manager `main.go`, `main.tsx`, `scripts/olc-backup.sh` |
| Полная переустановка | `scripts/olc-reinstall.sh` |
| Полное удаление | `scripts/olc-purge.sh` |
| Systemd | `packaging/systemd` |
| OlcRTC core patches | `patches/` и соответствующие core-скрипты |

## Production-сборка manager

```text
components/olcrtc-manager/src/main.tsx
        │ npm run build
        ▼
components/olcrtc-manager/cmd/olcrtc-manager/web/dist
        │ go:embed + go build
        ▼
/usr/local/bin/olcrtc-manager
```

Никакого клонирования manager, выбора `stable/latest` или копирования
golden-panel в этом пути нет. Upstream manager проверяется отдельно, а выбранные
изменения адаптируются прямо в vendored-исходник.

## Обязательная проверка изменений manager

```bash
cd components/olcrtc-manager
npm ci
npm run test:ui-backup
npm run build
go test ./...
cd ../..
OLC_ALLOW_VENDORED_BUILD_STATE=1 \
  bash scripts/verify-vendored-manager.sh components/olcrtc-manager
```

После изменения shell-скриптов: `bash -n` и профильные тесты из `scripts/test-*`.
Live-проверка сначала выполняется на API-VPS, production RU не меняется до
отдельного согласования.

## Правило backup

Любое поле, переключатель, список, порядок или другое состояние, меняемое
пользователем, должно переживать export/import. Серверное состояние хранится в
`config.json` или инвентаре `backupExtraFiles()`. Постоянное браузерное состояние
использует стабильный ключ `olc-*` и попадает в `ui_preferences`. Изменение схемы
требует новой версии и последовательного мигратора. См. [BACKUP.md](BACKUP.md).

## Legacy

`apply-olcrtc-patches.sh` остаётся активным оркестратором: он патчит OlcRTC core,
копирует vendored manager во временный build-каталог и собирает оба бинарника.
Только его ветка `OLC_MANAGER_LEGACY_PATCHSTACK=1`, manager `patch-*`,
`packaging/golden-panel` и экспорт golden-panel являются миграционным материалом.
Их физическое удаление выполняется отдельным подтверждённым cleanup после
перевода production и проверки отката.
