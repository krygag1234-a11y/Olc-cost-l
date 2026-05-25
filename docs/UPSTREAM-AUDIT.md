# Аудит: Olc-cost-l vs upstream (2026-05-25)

Сверка с оригиналами:

- [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) — pin `af9eeea`
- [BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel) — pin `ad8ec6f6`

## Выводы (кратко)

| Компонент | Upstream | Olc-cost-l | Влияние |
|-----------|----------|------------|---------|
| olcrtc `af9eeea` | Jitsi join ~1 с, YAML как в [examples/server.jitsi.datachannel.yaml](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/examples/server.jitsi.datachannel.yaml) | + `internal/routing/*`, split SOCKS, debounce/jitsi patches | **Бинарник olcrtc корректен**; без Tor в YAML Jitsi стабилен |
| manager `ad8ec6f6` | `serverConfig` **без** SOCKS/Tor, **без** liveness в YAML | + SOCKS split, `link=tor` по умолчанию, relaxed liveness | **Адаптация manager** — нужна для RU VPS, но отличается от upstream |
| Панель (много клиентов) | 1 процесс на location | 3–5+ Jitsi на разные комнаты cryptopro | **Главный источник флапов** Prosody (`Error loading roster`) |

Проверка на VPS (2026-05-25):

```text
/tmp/olcrtc-upstream-bin + minimal YAML (как upstream) → joined за ~1 с
/usr/local/bin/olcrtc + minimal YAML → joined за ~1 с
/usr/local/bin/olcrtc + manager YAML (tor+split) → join 75% OK, 25% bind rejected (Prosody)
```

Ошибка `xmpp dial: bind: ... Error loading roster` — ответ **meet.cryptopro.ru**, не баг сборки. Усиливается при нескольких одновременных join с одного IP.

## Что в upstream уже есть

- YAML-only CLI (`olcrtc config.yaml`)
- `auth.provider`: jitsi / wbstream / telemost
- `net.transport`: datachannel (jitsi stable), vp8channel (wb/telemost stable)
- `socks.proxy_addr` / `proxy_port` в схеме, но **без** split-файлов
- `liveness`: 10s / 5s / 3 failures

## Что добавляет только Olc-cost-l (нужно для RU VPS)

| Патч / файл | Зачем |
|-------------|--------|
| `patches/olcrtc-routing-*.go` + `patch-olcrtc-core.sh` | Split RU direct / Tor — **в upstream af9eeea нет** |
| `patch-olcrtc-manager-socks.sh` | Проброс `direct_*` / `blocked_tor_*` в YAML |
| `patch-olcrtc-manager-default-link-tor.sh` | `link: tor` для туннеля (upstream manager — direct only) |
| `patch-olcrtc-server-jitsi-no-smux-reconnect.sh` | Не рвать VPN при flap Jitsi bridge |
| `patch-j-xmpp-bind-fastfail.sh` | Явная ошибка bind вместо 60s EOF |

## Рекомендуемые carrier/transport (upstream docs)

| Carrier | Transport | Примечание |
|---------|-----------|------------|
| jitsi | **datachannel** | Стабильно |
| wbstream | **vp8channel** | datachannel не работает |
| telemost | **vp8channel** | datachannel не работает |

## Операционные правила

1. **Один Jitsi-клиент** на одну комнату в панели (отключить дубликаты Exams/Shop/ShopSmoothly).
2. Liveness в YAML — как upstream (`10s` / `5s` / `3`), не завышать.
3. После обновления: `apply-olcrtc-patches.sh` + `systemctl restart olcrtc-manager`.
4. Tor должен быть жив (`OLCRTC_EXIT_PROXY`); иначе manager запускает olcrtc **без** SOCKS (см. `exitProxyReachable`).

## Что не коммитить в публичный репо

- IP VPS, пароли panel.env, `PROJECT-STATE.md`
