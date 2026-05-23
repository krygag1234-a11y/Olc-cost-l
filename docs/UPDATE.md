# Установка и обновление

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
```

| Состояние VPS | Действие |
|---------------|----------|
| `fresh` | `agent-bootstrap.sh --full` |
| `installed` / `partial` | `agent-bootstrap.sh --update` |

Симлинк: `/opt/olcrtc` → `/opt/Olc-cost-l`

## Ручные режимы

```bash
sudo bash install.sh --full
sudo bash install.sh --update
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --rebuild-only
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --full --no-tor   # foreign VPS
```

## Что делает `--update`

1. `git pull` (в `install.sh`)
2. Пересборка патченных `olcrtc` / `olcrtc-manager`
3. `setup-split-ru.sh` — CIDR и домены
4. `configure-tor-exit.sh` — ExitNodes
5. `install-tor-pluggable-transports.sh` + обновление пула мостов
6. systemd: manager, pool/monitor/**deep** timers, healthcheck cron
7. zapret (RU VPS, если включён)
8. `systemctl restart olcrtc-manager`

`torrc` и `bridges.conf` не сносятся; pool дополняется.

## После обновления

```bash
systemctl is-active tor@default olcrtc-manager
systemctl list-timers 'olcrtc-tor-bridge-*' --no-pager
curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
grep '^Bridge ' /etc/tor/bridges.conf | sed 's/ .*//' | uniq -c
journalctl -u olcrtc-manager -n 30 --no-pager | grep route=
```

## Tor (после обновления, опционально)

```bash
sudo /opt/Olc-cost-l/scripts/fetch-bridge-extra-sources.sh
sudo /opt/Olc-cost-l/scripts/tor-bridge-deep-check.sh --from-pool --limit 8 --jobs 2
sudo /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --apply
```
