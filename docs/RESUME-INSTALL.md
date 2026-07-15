# [DEV] Resumable install / update

> **Этот документ для разработчиков.** Пользователям он не нужен для установки и работы.

Шаги `install.sh` / `agent-bootstrap.sh` идемпотентны и записываются в `/var/lib/olcrtc/install-state.json`. Если что-то порвалось посередине (упал ssh, timeout на gitlab, прервался zapret) — повторный запуск **продолжит с последнего успешного шага**.

## Использование

```bash
# Любой запуск пишет state. Если упало:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh \
  | sudo bash -s -- --resume

# Посмотреть, на каком шаге упало:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh \
  | sudo bash -s -- --state

# Локально, если репо уже клонирован:
sudo /opt/Olc-cost-l/scripts/agent-bootstrap.sh --state
sudo /opt/Olc-cost-l/scripts/agent-bootstrap.sh --update --resume
sudo OLCRTC_FORCE_STEP=zapret /opt/Olc-cost-l/scripts/agent-bootstrap.sh --update --resume
```

### Флаги версии панели при resume

- `` — продолжить с стабильной версией
- `--manager-latest` — продолжить с последней upstream
- без флага — продолжить с pinned версией

### Автообновление SHA256

Если при обновлении `golden-panel` checksum не совпадает:

```bash
sudo /opt/Olc-cost-l/scripts/agent-bootstrap.sh --update --resume --force-sha-update
```

## Поведение по шагам

| Шаг                     | Soft-fail | Что значит fail                                       |
| ----------------------- | --------- | ----------------------------------------------------- |
| `packages`              | нет       | apt не вышел — без него ничего не построить           |
| `patches` / `webtunnel` | webtunnel: да | Без webtunnel будут только obfs4 бриджи            |
| `sysctl` / `cron`       | да        | Не критично для запуска панели                        |
| `tor` / `bridges`       | да        | Если bridges не скачались — будут добавлены позже cron|
| `split`                 | да        | Сплит-листы пустые — весь трафик пойдёт через Tor exit|
| `zapret`                | да        | Без него заблокированные .ru идут direct без DPI обхода|
| `systemd` / `start-manager` | нет   | Без них панель не поднимется                          |

«Soft» — `state_step` отметит как ok и продолжит, чтобы установка дошла до конца. Чтобы потом переустановить конкретный шаг:

```bash
sudo OLCRTC_FORCE_STEP=zapret /opt/Olc-cost-l/scripts/agent-bootstrap.sh --update --resume
```

## Сброс state (полная переустановка)

```bash
sudo /opt/Olc-cost-l/scripts/agent-bootstrap.sh --full --fresh-state
```

## Где state

`/var/lib/olcrtc/install-state.json`:

```json
{
  "started": "2026-05-26T...",
  "last_ok": "tor",
  "history": ["packages","patches","webtunnel","tor",...],
  "failed": null,
  "finished": "2026-05-26T..."
}
```

`failed` будет `{ "step": "...", "code": N, "time": "..." }` после падения.

## Pre-built webtunnel из mirror

`scripts/lib-webtunnel-build.sh` сначала скачивает готовый binary с
`https://github.com/krygag1234-a11y/mirror-cry/releases/latest/download/webtunnel-client-linux-amd64`

Если релизов mirror-cry ещё нет — один раз с VPS (gitlab доступен):

```bash
export GITHUB_TOKEN=...
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/mirror-cry/main/scripts/mirror-webtunnel-publish.sh | bash
```
(зеркало, обновляемое GitHub Actions из gitlab.torproject.org), и только если зеркало недоступно — fallback на gitlab tarball / git clone. Это убирает зависимость RU VPS от gitlab.torproject.org, который у большинства RU провайдеров заблокирован.
