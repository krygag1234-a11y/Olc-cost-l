# Патчи OlcRTC core

Production manager хранится готовым исходником в `components/olcrtc-manager`.
Manager patch-stack, golden-panel и `local-panel-version` удалены. Во время
установки или обновления manager не патчится: его исходник проверяется
`scripts/verify-vendored-manager.sh`, копируется в изолированный build-каталог
и собирается как часть общей сборки.

## Что остаётся патчами

OlcRTC core — внешний проект, закреплённый в `data/upstream-pins.json`.
Совместимые изменения core применяет `scripts/apply-olcrtc-patches.sh`:

- routing CIDR/domain helpers из `patches/olcrtc-routing-*.go`;
- access hook и live key classes;
- key randomization в core;
- direct/Tor domain routing и route logging;
- reload debounce/skip/rwlock;
- Tor limits и reconnect fixes;
- Jitsi retry/extras;
- XMPP bind fast-fail.

Точный исполняемый порядок является источником истины и находится в функции
`apply_olcrtc()` файла `scripts/apply-olcrtc-patches.sh`.

## Проверка

```bash
# Проверить vendored manager
OLC_ALLOW_VENDORED_BUILD_STATE=1 \
  bash scripts/verify-vendored-manager.sh components/olcrtc-manager

# Чисто применить только core patches и подготовить vendored manager
sudo OLC_PATCH_ONLY=1 BUILD=0 bash scripts/apply-olcrtc-patches.sh

# Полная проверка manager
cd components/olcrtc-manager
npm ci
npm run test:ui-backup
npm run build
go test ./...
```

Upstream manager не применяется автоматически. Новые upstream-коммиты
классифицируются по `docs/UPSTREAM-SYNC.md`, а выбранные изменения вносятся
непосредственно в `components/olcrtc-manager`.
