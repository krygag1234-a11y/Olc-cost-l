# Синхронизация тестового VPS ↔ репозиторий

## Короткая команда для Cursor

> **синк olc** или **olc sync**

Агент запускает полный sync (не только golden):

```bash
sudo bash /opt/Olc-cost-l/scripts/olc-sync-from-vps.sh
```

**Не** деплоить старые скрипты на VPS без явной просьбы.

## Что делает `olc-sync-from-vps.sh`

| Шаг | Куда |
|-----|------|
| `main.tsx`, `main.go` с тестового VPS | `packaging/golden-panel/` + `SHA256SUMS` |
| `features.env`, panel.env (без паролей), systemd | `packaging/vps-snapshot/` |
| Проверка | `olc-panel-verify.sh` |
| Локальный снимок VPS | `olc-vps-snapshot.sh` → `packaging/vps-snapshot/` |

После скрипта: `git add`, `commit`, `push`.

## Только golden (быстро)

```bash
sudo bash /opt/Olc-cost-l/scripts/olc-export-golden-panel.sh
```

## Тестовый VPS

```bash
ssh -i ~/.ssh/test_vps_key user@test-vps-ip
```

## Установка с репо = тестовый UI

`install.sh --update` в конце вызывает `apply-golden-panel.sh` — копирует `packaging/golden-panel/` поверх патчей.

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --update
sudo olc-panel-verify
```

## Проверка диска

```bash
sudo olc-disk-check
```

Подробный план работ: `/root/.cursor/plans/olc-sync-test-vps-to-repo.md` (на машине разработки).
