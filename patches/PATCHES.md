# Патчи относительно upstream (обязательны для Jitsi + панель + RU VPS)

**Обновлено:** 2026-05-24  
**Ветка olcrtc:** [`master`](https://github.com/openlibrecommunity/olcrtc/tree/master)  
**Панель:** [`main`](https://github.com/BigDaddy3334/olcrtc-manager-panel)  
**Применение:** `scripts/apply-olcrtc-patches.sh` или `upstream-sync.sh --apply`

---

## Как применяются патчи (2026-05)

Старый monolithic `olcrtc-core.patch` **не применяется первым** — он ломался на свежем upstream. Вместо этого:

1. Клон `olcrtc` + `olcrtc-manager-panel` в `/tmp/olcrtc-src`, `/tmp/olcrtc-manager-panel`
2. **Idempotent shell-скрипты** `patch-olcrtc-*.sh` (можно гонять повторно)
3. Файлы целиком: `olcrtc-routing-cidr.go`, `olcrtc-routing-domains.go`
4. `install-go-toolchain.sh` → Go ≥1.23, `GOTOOLCHAIN=auto`
5. Сборка в `/usr/local/bin/olcrtc`, `/usr/local/bin/olcrtc-manager`
6. UI панели: `npm ci && npm run build` в clone manager (если есть `npm`)

---

## olcrtc ([openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc))

| Скрипт / файл | Зачем |
|---------------|--------|
| `patch-olcrtc-core.sh` | Jitsi payload **16K−12**; SOCKS split в server |
| `olcrtc-routing-cidr.go` | GeoIP RU CIDR matcher |
| `olcrtc-routing-domains.go` | Direct по домену |
| `patch-olcrtc-server-domains.sh` | `direct_domains_file` в server (domain-first) |
| `patch-olcrtc-server-blocked-tor.sh` | RF-blocked `.ru` → direct + zapret |
| `patch-olcrtc-server-force-tor.sh` | YouTube/global → always Tor |
| `patch-olcrtc-server-route-log.sh` | Лог `connect HOST route=direct\|tor` |
| `patch-olcrtc-server-reconnect-debounce.sh` | Debounce smux reconnect (**5s**) |
| `patch-olcrtc-server-jitsi-no-smux-reconnect.sh` | Jitsi bridge reconnect **без** smux tear-down |
| `patch-j-xmpp-bind-fastfail.sh` | Быстрый fail при Prosody `bind` error (не ждать 60s EOF) |
| `patch-olcrtc-jitsi-join-retry.sh` v3 | 6 ретраев с jitter, варьируется nick (избегает session-ghost), per-attempt timeout 14s; **cap=3 при подряд WS-dial-timeout** (хост недоступен — не жжём весь бюджет) |
| `patch-olcrtc-goolom-reconnect-stable.sh` | Стабильный reconnect carrier |
| `patch-olcrtc-goolom-reconnect-no-early-callback.sh` | Без раннего `onReconnect(nil)` |
| `olcrtc-session-direct-cidrs.patch` | (legacy) проброс `direct_cidrs_file` в session |

Legacy `.patch` в `patches/` — справочно; при конфликте ориентир на `patch-*.sh`.

---

## olcrtc-manager ([BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel))

| Скрипт | Зачем |
|--------|--------|
| `patch-olcrtc-manager-core.sh` | Логи API, liveness, базовые хуки |
| `olcrtc-manager-main.go.patch` | Fallback если нет `exitProxyReachable` |
| `patch-olcrtc-manager-socks.sh` | SOCKS + `ForceTorDomainsFile`, exit proxy |
| `patch-olcrtc-manager-domains.sh` | `direct_domains_file`, `blocked_tor`, force-tor |
| `patch-olcrtc-manager-link-direct.sh` | `link: direct` на локации |
| `patch-olcrtc-manager-default-link-tor.sh` | Новые локации → `link: tor` |
| `patch-olcrtc-manager-panel-link.sh` | UI шлёт `link` в API |
| `patch-olcrtc-manager-panel-transports.sh` | Transports Olcbox (DC/VP8/SEI) |
| `patch-olcrtc-manager-panel-vp8-defaults.sh` | VP8 **50/50** по умолчанию |
| `patch-olcrtc-manager-sessions.sh` | Сессии на диск |
| `patch-olcrtc-manager-host-network.sh` | `HOST_NETWORK` |
| `patch-olcrtc-manager-vps-extras.sh` | `PUBLIC_URL`, VPS extras |
| `patch-olcrtc-manager-room-binding.sh` | Room ID без лишнего URL |
| `patch-olcrtc-manager-runtime-dir.sh` | YAML в `/var/lib/olcrtc/manager-run` |
| `patch-olcrtc-manager-postcss.sh` | PostCSS для сборки UI |
| `patch-olcrtc-manager-features.sh` | `/api/features` + `/api/features/{name}` для toggle zapret/tor/split/webtunnel |
| `patch-olcrtc-manager-panel-features.sh` | UI-карточка «Network features» в `/admin` |

---

## Списки и инфра (не патчи исходников)

| Скрипт | Зачем |
|--------|--------|
| `fetch-geosite-ru-domains.sh` | ~20k правил из ru-routing-dat |
| `fetch-player-cdn-domains.sh` | RU video CDN |
| `fetch-ru-blocked-tor-domains.sh` | RF-blocked → direct |
| `fetch-force-tor-domains.sh` | YouTube → Tor |
| `configure-tor-exit.sh` | ExitNodes EU, exclude RU/CIS |
| `discover-page-hosts.sh` | Домены со страницы плеера |
| `install-zapret-vps.sh` | Zapret nfqws на direct |
| `sync-zapret-hostlist.sh` | Hostlist zapret |
| `data/ru-domains-extra.txt` | CDN вне `*.ru` |

---

## Carriers (Jitsi / WB / Telemost)

| Carrier | Transport | Примечание |
|---------|-----------|------------|
| **jitsi** | datachannel | Стабильный baseline |
| **wbstream** | **vp8channel** 50/50 | Предпочтительнее seichannel |
| **telemost** | datachannel 45/45 | Reconnect debounce в olcrtc |

---

## Обновление upstream

```bash
/opt/Olc-cost-l/scripts/upstream-sync.sh --check
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --apply
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --apply --zapret
```

Логи неудач: `/var/lib/olcrtc/upstream-review/`

---

## Клиент Olcbox

| Сборка | URL |
|--------|-----|
| Nightly | https://github.com/alananisimov/olcbox/releases/tag/nightly |
| Releases | https://github.com/alananisimov/olcbox/releases |
