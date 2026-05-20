# Патчи относительно upstream (обязательны для Jitsi + панель + RU VPS)

Ветка olcrtc: **`refactor/universal-carrier`** (не `main`).  
Документация upstream может не совпадать с кодом — ориентир: исходники.

## olcrtc ([openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc/tree/refactor/universal-carrier))

| Патч | Зачем |
|------|--------|
| `olcrtc-core.patch` | Jitsi payload 16K-12; split RU/direct vs Tor SOCKS |
| `olcrtc-routing-cidr.go` | Новый файл `internal/routing/cidr.go` |

## olcrtc-manager ([BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel))

| Патч | Зачем |
|------|--------|
| `olcrtc-manager-main.go.patch` | Логи `/api/logs?query`; Jitsi liveness; `OLCRTC_HOST_NETWORK`; `OLCRTC_EXIT_PROXY` только если Tor жив; `OLCRTC_PUBLIC_URL`; `bindingRoomURL` (Telemost); `direct_cidrs_file` |

## Клиент

[olcbox nightly-universal-carrier](https://github.com/alananisimov/olcbox/releases/tag/nightly-universal-carrier) — под ветку `refactor/universal-carrier`.

Применение: `/opt/Olc-cost-l/scripts/apply-olcrtc-patches.sh`
