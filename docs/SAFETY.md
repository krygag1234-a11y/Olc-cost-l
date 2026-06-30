# [DEV] Безопасность скриптов

> **Этот документ для разработчиков.** Пользователям он не нужен для установки и работы.

Скрипты **не предназначены** для произвольного запуска на десктопе без root на продакшен-VPS без бэкапа.

Центр проверок: `scripts/safety-lib.sh` — allowlist путей записи, whitelist ключей `panel.env`, запрет опасных `OUT=` / `TORRC=` / git clone не в `/tmp`.

## Что скрипты НЕ делают

| Действие | Статус |
|----------|--------|
| `iptables -F`, `ufw reset`, `ip route flush` | **нет** |
| Правка `/etc/ssh`, `authorized_keys`, `sshd_config` | **нет** |
| Удаление `/etc`, `/usr`, `/var` целиком | **нет** |
| Перезапись целиком `/etc/tor/torrc` | **нет** (только append + `%include`) |
| `sysctl --system` (глобальный reload) | **нет** с 2026-05-22 — только `sysctl -p 99-olcrtc-performance.conf` |
| Правка чужого `/etc/crontab` | **нет** с 2026-05-22 — отдельный `/etc/cron.d/olcrtc-healthcheck` |
| `git checkout -f` вне `/tmp` | **запрещено** (`apply-olcrtc-patches.sh`) |
| `chmod 777` на системные каталоги | **нет** |

## Куда можно писать (allowlist)

| Путь | Действие |
|------|----------|
| `/etc/olcrtc-manager/` | `config.json`, `panel.env` (только ключи `OLCRTC_DIRECT_*`, `OLCRTC_BLOCKED_TOR_*`) |
| `/etc/tor/bridges.conf` | мосты (с бэкапом `.bak.*`) |
| `/etc/tor/torrc` | только append: `%include`, `SocksPolicy` localhost |
| `/etc/systemd/system/olcrtc-*` | юниты OlcRTC |
| `/etc/cron.d/olcrtc-healthcheck` | healthcheck каждые 10 мин |
| `/etc/sysctl.d/99-olcrtc-performance.conf` | BBR (удалить файл = откат) |
| `/etc/apparmor.d/local/system_tor` | строка для `webtunnel-client` |
| `/var/lib/olcrtc/` | списки CIDR/доменов, пул мостов |
| `/var/log/olcrtc-*` | логи health/bridges/deep-check |
| `/tmp/tor-deep.*` | временные tor для deep-check (удаляются) |
| `/usr/local/bin/olcrtc*` | бинарники после сборки |
| `/usr/bin/webtunnel-client` | PT Tor |
| `/tmp/*`, `/var/tmp/*` | git clone для сборки |

## Переменные окружения

При ошибочном `OUT=/etc/passwd` или `BRIDGES_OUT=/etc/hosts` скрипт **завершится с REFUSE**.

`OLC_INSTALL_DIR` не может быть `/`, `/etc`, `/usr`, `/root`.

## Симлинк `/opt/olcrtc`

`agent-bootstrap` / `install.sh` создают ` /opt/olcrtc` → каталог репо.  
Если `/opt/olcrtc` уже **существует как обычная папка** (не symlink) — скрипт **откажется** перезаписать (защита от потери данных).

## Tor

- `systemctl restart tor@default` — краткий обрыв SOCKS; **SSH не трогается**
- `SocksPolicy` ограничивает SOCKS **127.0.0.1** (`secure-local-tor.sh`)
- При сбое Tor manager продолжает Jitsi **без** exit proxy (патч `exitProxyReachable`)

## Сеть / split

- Маршрутизация только **внутри olcrtc** (direct vs Tor SOCKS), не на уровне ОС
- Списки — файлы в `/var/lib/olcrtc/`, не `ip rule`

## Рекомендации перед деплоем

1. Снимок VPS или бэкап `/etc/tor`, `/etc/olcrtc-manager`
2. SSH-сессию не закрывать до `systemctl status olcrtc-manager`
3. Порт **8888** — пароль в `/admin`
4. Токены GitHub **не коммитить**

## Откат

```bash
systemctl stop olcrtc-manager tor@default
rm -f /etc/cron.d/olcrtc-healthcheck
mv /etc/tor/bridges.conf.bak.* /etc/tor/bridges.conf   # последний бэкап
systemctl disable olcrtc-tor-bridge-pool.timer olcrtc-tor-bridge-monitor.timer
rm -f /etc/sysctl.d/99-olcrtc-performance.conf
sysctl -p /etc/sysctl.d/10-*.conf 2>/dev/null || true
```

## Проверка REFUSE (на VPS)

```bash
OUT=/etc/passwd bash /opt/Olc-cost-l/scripts/fetch-ru-cidrs.sh   # должен выйти с ошибкой
OLCRTC_REPO=/etc bash /opt/Olc-cost-l/scripts/apply-olcrtc-patches.sh  # должен REFUSE
```
