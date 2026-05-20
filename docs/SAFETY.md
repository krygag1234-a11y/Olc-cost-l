# Безопасность скриптов

Скрипты **не предназначены** для произвольного запуска на десктопе или без root на продакшен-VPS без бэкапа.

## Что скрипты НЕ делают

- Не трогают `/etc/ssh/sshd_config`, ключи, `authorized_keys`
- Не выполняют `iptables -F`, `ip route flush`, не меняют дефолтный gateway
- Не удаляют и не перезаписывают целиком `/etc/tor/torrc` (только `%include` для `bridges.conf`)
- Не удаляют файлы вне allowlist (`scripts/safety-lib.sh`)
- Не ставят `chmod 777` на системные каталоги

## Куда можно писать

| Путь | Действие |
|------|----------|
| `/etc/olcrtc-manager/` | config, panel.env |
| `/etc/tor/bridges.conf` | мосты (с бэкапом `.bak.*`) |
| `/etc/tor/torrc` | только добавление `%include` |
| `/etc/systemd/system/olcrtc-*` | юниты OlcRTC |
| `/var/lib/olcrtc/` | пул мостов, health, RU CIDR |
| `/usr/local/bin/olcrtc*` | бинарники после сборки |
| `/etc/sysctl.d/99-olcrtc-performance.conf` | BBR (можно удалить) |

## Рекомендации

1. Перед первым запуском: снимок VPS или бэкап `/etc/tor`, `/etc/olcrtc-manager`.
2. SSH-сессию не закрывать до проверки `systemctl status olcrtc-manager`.
3. Порт **8888** открыть только при необходимости; сразу задать пароль в `/admin`.
4. Токены GitHub **никогда** не коммитить в репозиторий.

## Tor

- `systemctl restart tor@default` — краткий обрыв SOCKS; не ломает SSH.
- При сбое Tor manager продолжает Jitsi **без** exit proxy (патч `exitProxyReachable`).

## Откат

```bash
systemctl stop olcrtc-manager tor@default
mv /etc/tor/bridges.conf.bak.* /etc/tor/bridges.conf  # последний бэкап
systemctl disable olcrtc-tor-bridge-pool.timer olcrtc-tor-bridge-monitor.timer
```
