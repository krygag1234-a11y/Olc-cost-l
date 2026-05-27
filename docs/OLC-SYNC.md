# Синхронизация тестового VPS ↔ репозиторий

## Короткая команда для Cursor

Напиши агенту:

> **синк olc**

или

> **olc sync**

Агент должен: взять состояние с тестового VPS → обновить [Olc-cost-l](https://github.com/krygag1234-a11y/Olc-cost-l) → push. **Не** деплоить старые скрипты на VPS без синка.

## Тестовый VPS

```bash
ssh -i /root/.ssh/yandex_bm_test_key kryga@89.169.186.195
```

IP может измениться — обновите в `.cursor/rules/olc-olcrtc-workflow.mdc`.

## Проверка диска

Перед install/update скрипты проверяют место на `/` и `/tmp`. При нехватке — сообщение **на русском** (не только `No space left on device`).

```bash
sudo olc-disk-check
```

Переменные: `OLC_DISK_MIN_MB_ROOT`, `OLC_DISK_CHECK_DISABLE=1`, `OLC_DISK_CHECK_WARN_ONLY=1`.

## Пути на VPS

| Путь | Назначение |
|------|------------|
| `/opt/Olc-cost-l` | Клон репозитория, скрипты |
| `/tmp/olcrtc-manager-panel` | Панель после `apply-olcrtc-patches.sh` |

## Панель в репо

Исходники панели не хранятся целиком в Olc-cost-l — только **патчи** в `scripts/patch-olcrtc-manager-*.sh`. После правок на VPS добавляйте/обновляйте патч (например `patch-olcrtc-manager-panel-hotfix-v20.sh`) и строку в `apply-olcrtc-patches.sh`.
