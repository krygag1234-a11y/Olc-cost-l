# Установка и обновление (одна ссылка)

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
```

Скрипт сам определяет состояние:

| `olc-detect-install.sh` | Действие `install.sh` |
|-------------------------|------------------------|
| `fresh` | `agent-bootstrap.sh --full` |
| `installed` / `partial` | `agent-bootstrap.sh --update` |

Признаки установки: репо `/opt/Olc-cost-l`, `olcrtc-manager`, `panel.env`, юниты `olcrtc-*`.

## Ручные режимы

```bash
sudo bash install.sh --full      # принудительно: apt deps + полная сборка
sudo bash install.sh --update    # только обновление
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --rebuild-only
```

## Что делает `--update`

1. `git pull` (уже в `install.sh`)
2. Пересборка патченных `olcrtc` / `olcrtc-manager`
3. `setup-split-ru.sh` — списки CIDR/доменов
4. `configure-tor-exit.sh` — ExitNodes без RU
5. systemd/cron из packaging
6. `systemctl restart olcrtc-manager`

Tor и мосты не сносятся; `torrc` только дополняется.

## После обновления

```bash
journalctl -u olcrtc-manager -f | grep 'route='
grep OLCRTC_ /etc/olcrtc-manager/panel.env
```
