# Zapret / DPI (опционально, вне туннеля Olcbox)

[Zensey/split-tunnel](https://github.com/Zensey/split-tunnel) и [ChiefGyk3D/split_tunnel_switch](https://github.com/ChiefGyk3D/split_tunnel_switch) — **маршрутизация на Windows/Linux у клиента**, не замена split на VPS.

## Что даёт Olc-cost-l без zapret

| Механизм | Назначение |
|----------|------------|
| `*.ru` builtin | Страницы RU direct |
| `ru-direct-domains.txt` | Плееры/CDN direct (RU IP) |
| `ru-blocked-tor-domains.txt` | Заблокированные .ru → **Tor** |

## Когда нужен zapret4rocket / zapret

- Провайдер режет **TLS/DPI** по сигнатурам, а не только по IP.
- **Tor** не поднимается (блок сети Tor) — список `blocked-tor` бесполезен без мостов.
- Нужен обход **на самом VPS** для исходящих direct-подключений olcrtc.

Zapret на VPS — **отдельная установка** (nfqueue, `iptables`, обновление списков). В репозиторий **не входит** автоматически: слишком хрупко для общего install.sh.

Ориентиры (ставить вручную на RU VPS под root):

1. Клонировать актуальный форк zapret / [zapret4rocket](https://github.com/search?q=zapret4rocket&type=repositories) по README форка.
2. Запускать в режиме **nfqws** для исходящего трафика с хоста (olcrtc уже в host network).
3. Списки доменов синхронизировать с теми же, что в `ru-blocked-tor` / antifilter.

**Не смешивать** с `OLCRTC_INCLUDE_CDN_IPS=1` (CDN /32 → 404 nginx).

## Практическая схема

```
Olcbox → VPS olcrtc → direct (*.ru + player CDN)
                    → tor (зарубежное + ru-blocked-tor list)
VPS host (опционально) → zapret nfqws для direct HTTPS к DPI-блокам
```

После установки zapret проверьте с VPS: `curl -I https://заблокированный.ru` без туннеля.
