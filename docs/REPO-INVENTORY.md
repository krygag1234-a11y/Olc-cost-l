# Инвентаризация репозитория Olc-cost-l

**Дата:** 2026-05-28  
**Эталон UI:** `packaging/golden-panel/` (синк с тестового VPS `kryga@89.169.186.195`)

## Golden panel (фаза 3)

| Файл | Назначение |
|------|------------|
| `packaging/golden-panel/main.tsx` | SPA (~5.2k строк), i18n ru/en, instance defaults, LogScroll |
| `packaging/golden-panel/main.go` | Backend manager, `/api/panel/lang`, instance-defaults |
| `packaging/golden-panel/SHA256SUMS` | Контроль целостности |

Применение: `scripts/apply-golden-panel.sh` (через `install.sh` / bootstrap).

## Патчи (фаза 2)

~145 скриптов `scripts/patch-olcrtc-manager*.sh` — исторические инкременты до golden overlay.

**Стратегия:** новые фичи → сначала тест VPS → `olc-sync-from-vps.sh` → golden; патчи только для обратной совместимости install на старых VPS.

## Upstream pins

`data/upstream-pins.json` — фиксация веток olcrtc, manager-panel и др.

## VPS snapshot

`packaging/vps-snapshot/` — `features.env`, `panel.env.example`, systemd units, commit hash (без секретов).

## GAP vs upstream

См. `docs/INTEGRATION-GAP.md` (Tor/split, zapret, liveness, VP8 defaults).

## Транспорты (7.3)

| Где | videochannel |
|-----|----------------|
| UI новые локации | Убран из `transportsByCarrier` |
| UI legacy | Показ с меткой «устар.», поля payload сохранены |
| Backend `isSupported` | `false` для всех carrier |
| Backend parse/validate | Оставлен для существующих config |

## Синк

```bash
sudo bash /opt/Olc-cost-l/scripts/olc-sync-from-vps.sh
```

## Скрипты проверки

| Скрипт | Назначение |
|--------|------------|
| `olc-sync-from-vps.sh` | Тест VPS → golden + snapshot |
| `olc-test-vps-preflight.sh` | cmp golden vs `/tmp/olcrtc-manager-panel` на тесте (без деплоя) |
| `olc-panel-verify.sh` | cmp golden vs локальный build в `/tmp/olcrtc-manager-panel` |

## 7.5 Пул мостов Tor (webtunnel → bridges.conf)

| Проблема | `runBridgePoolRefresh` вызывал только `--fetch` → pool обновлялся, `bridges.conf` — нет |
| Исправление | Полный `tor-bridge-pool.sh --types …`; API `refresh_pool` в `componentSettingsHandler` |
| Финальный merge | **Обязательно** включить в golden `main.go` (см. план §7.5, чеклист фазы 8) |

Проверка: «Настройки → Мосты → Обновить пул» → в превью/conf есть `Bridge webtunnel` и `ClientTransportPlugin webtunnel`.

## Открыто

- [ ] `install.sh --update` на чистом тесте (фаза 3.5 / 6) — только после preflight OK
- [ ] **7.5.4** в финальный merge репо
- [x] i18n форм zapret/tor/split/warp/bridges (основные подписи)
- [x] 7.3.3 legacy videochannel
- [ ] `olc-panel-verify` в CI (фаза 8.4)
