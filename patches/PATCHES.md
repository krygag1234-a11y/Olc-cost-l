# Патчи относительно upstream (обязательны для Jitsi + панель + RU VPS)

Ветка olcrtc: **`master`** (ветка `refactor/universal-carrier` удалена после merge).  
Документация upstream может не совпадать с кодом — ориентир: исходники.

## olcrtc ([openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc/tree/master))

- `olcrtc-session-direct-cidrs.patch` — проброс `direct_cidrs_file` в `session.Config` (на master поле есть в YAML, но не в session до патча).

| Патч | Зачем |
|------|--------|
| `olcrtc-core.patch` | Jitsi payload 16K-12; split RU/direct vs Tor SOCKS |
| `olcrtc-routing-cidr.go` | `internal/routing/cidr.go` — GeoIP RU |
| `olcrtc-routing-domains.go` | `internal/routing/domains.go` — direct по домену |
| `olcrtc-domains-split.patch` | `direct_domains_file` в config/server |
| `olcrtc-session-domains.patch` | проброс в session → server |

## olcrtc-manager ([BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel))

| Патч | Зачем |
|------|--------|
| `olcrtc-manager-main.go.patch` | Логи API; liveness; HOST_NETWORK; EXIT_PROXY; PUBLIC_URL; `direct_cidrs_file` + `direct_domains_file` |

## Клиент

| Olcbox | https://github.com/alananisimov/olcbox/releases/tag/nightly |
| Olcbox (стабильная ссылка) | https://github.com/alananisimov/olcbox/releases |

Применение: `/opt/Olc-cost-l/scripts/apply-olcrtc-patches.sh`
