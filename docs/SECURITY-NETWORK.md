# Безопасность: SOCKS, Tor, авторизация

## Что есть на VPS

| Сервис | Адрес | Авторизация | Доступ из интернета |
|--------|--------|-------------|---------------------|
| **Панель** | `:8888` | Да — `panel.env` (`OLCRTC_MANAGER_USER` / `OLCRTC_MANAGER_PASS`), cookie после входа | Часто `0.0.0.0` — **задайте сильный пароль**, лучше nginx + TLS |
| **Tor SOCKS** | `127.0.0.1:9050` | Нет (стандарт Tor) | **Только localhost** — `secure-local-tor.sh` добавляет `SocksPolicy reject *` для остальных |
| **olcrtc srv** | — | Нет публичного SOCKS | Клиент подключается по **WebRTC/Jitsi**, не по открытому SOCKS на VPS |

На VPS **нет** «голого» SOCKS5 для всего интернета. Outbound Tor виден только процессу `olcrtc` на localhost.

## SOCKS5 с логином/паролем (Olcbox)

На **телефоне/ПК** Olcbox поднимает локальный SOCKS `127.0.0.1:10808` с **уникальными** `username` / `password` на сессию (см. лог `olcRTC ready`). Это **RFC 1929** (username/password), не HTTP Proxy-Authorization.

Протокол olcrtc в `socks:` YAML поддерживает `user` / `pass` для режима **cnc** (клиент-слушатель). Режим **srv** на VPS эти поля для входящих не использует — туннель идёт через carrier.

## HTTP-авторизация

Туннель **не** раздаёт HTTP-proxy с Basic auth. Приложения ходят в **SOCKS5** (Olcbox TUN → локальный SOCKS). Сайты с HTTP Basic — как обычно через браузер поверх SOCKS.

## Split и «голый» exit

- **RU IP + CDN/плееры** → direct (ваш VPS IP, без Tor exit).
- **Остальное** → Tor exit (если задан `OLCRTC_EXIT_PROXY`).

Плееры «недоступно в регионе» — CDN видел Tor exit; списки `ru-player-cdn` + `cdn-direct` решают это на **RU VPS** (`setup-split-ru.sh`).

## Рекомендации

1. Сильный пароль панели, не светить `panel.env`.
2. UFW: `8888/tcp` только с ваших IP, SSH ограничить.
3. После установки: `scripts/secure-local-tor.sh`.
4. Иностранный VPS: `--no-tor` / `--foreign` — без split-скриптов и без Tor.
