# Эталон панели (golden-panel)

Файлы `main.tsx` и `main.go` — **рабочая** панель с тестового VPS.

При `install.sh --update` (без `--manager-stable`) скрипт `scripts/apply-golden-panel.sh` копирует их в `/tmp/olcrtc-manager-panel` после цепочки hotfix-патчей, затем `npm run build` + `go build`.

## Stable fork vs golden-panel

- **Stable fork** (`--manager-stable`): Отдельный репозиторий https://github.com/krygag1234-a11y/local-panel-version с проверенными патчами, не требует `apply-golden-panel.sh`
- **Golden-panel**: Fallback для pinned/latest версий, применяется через `apply-golden-panel.sh`

## Обновить эталон после правок на тестовом VPS

Синхронизация происходит через внутренние скрипты разработчика (расположенные вне репозитория).

## Проверка SHA256

Если checksum не совпадает при обновлении:

```bash
sudo olc-update --manager-stable --force-sha-update
```

Ожидаемый JS-bundle (vite hash): `index-BgVOK4FZ.js` (может измениться после правок эталона).
