# HTTPS панели по публичному IP

Панель поддерживает три режима транспорта:

- `--https-letsencrypt` — доверенный короткоживущий сертификат Let's Encrypt непосредственно для публичного IPv4;
- `--https-self-signed` (также `--https`) — локальный self-signed сертификат с IP в SAN, браузер покажет предупреждение;
- `--http` — HTTP без TLS.

Без явного выбора `--full` использует HTTPS с self-signed сертификатом. В интерактивных меню установки и обновления доступны все три режима; доверенный Let's Encrypt предлагается отдельным пунктом.

## Доверенный сертификат без домена

Домен не нужен. Требования:

1. стабильный публичный глобальный IPv4;
2. входящий TCP-порт 80 доступен из интернета и не занят другим локальным процессом во время проверки;
3. панель доступна по адресу `https://ПУБЛИЧНЫЙ_IP:8888/admin`.

Установка:

```bash
sudo bash install.sh --full --ip --https-letsencrypt
```

Обновление или переключение существующей установки:

```bash
sudo olc-update --ip --https-letsencrypt
```

Установщик находит Certbot 5.4+ либо ставит отдельное окружение в `/opt/olc-certbot`, затем запрашивает IP-сертификат с профилем `shortlived`. Если проверка IP не проходит, скрипт завершает операцию с ошибкой и не переключает панель молча на HTTP или self-signed.

## Автопродление

Создаются:

- `olc-certbot-renew.service`;
- `olc-certbot-renew.timer` — проверка каждые 6 часов со случайной задержкой до 30 минут;
- deploy-hook `/etc/letsencrypt/renewal-hooks/deploy/olc-manager-restart`.

После фактического обновления сертификата hook перезапускает `olcrtc-manager.service`, чтобы процесс перечитал новые файлы. Таймер постоянный: пропущенная во время выключения проверка запускается после старта VPS.

Диагностика:

```bash
systemctl status olc-certbot-renew.timer
systemctl list-timers olc-certbot-renew.timer
journalctl -u olc-certbot-renew.service
/opt/olc-certbot/bin/certbot certificates
```

## Self-signed и HTTP

```bash
sudo olc-update --ip --https-self-signed
sudo olc-update --ip --http
sudo olc-update --ssh --http
```

Сохранённый deploy-profile хранит отдельно способ доступа (`ip`/`ssh`) и TLS-режим (`letsencrypt`/`selfsigned`/`http`), поэтому последующие обновления повторяют выбранную схему.
