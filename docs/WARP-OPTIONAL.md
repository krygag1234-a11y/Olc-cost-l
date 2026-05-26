# Cloudflare WARP (опционально)

WARP — альтернатива Tor на **зарубежном** VPS: локальный SOCKS5-прокси Cloudflare (`warp-cli` в режиме **proxy only**), без переписывания default route.

## Когда использовать

| Сценарий | Профиль / флаг |
|----------|----------------|
| RU VPS, Tor + split + zapret | `ru-full` (WARP выключен) |
| Foreign relay без Tor | `foreign-minimal` |
| Foreign + WARP вместо Tor | `foreign-warp` или `install.sh --with-warp` |

## Установка

```bash
# При первой установке
curl -fsSL .../install.sh | sudo bash -s -- --with-warp

# На уже установленном VPS
sudo /opt/Olc-cost-l/scripts/install-warp.sh
sudo olc-feature warp on

# Профиль деплоя
sudo olc-profile set foreign-warp
```

Лог: `/var/log/olcrtc-warp-install.log`

## Безопасность (SSH)

`install-warp.sh` **принудительно** использует `mode=proxy`:

- снимок default route до настройки (`/var/lib/olcrtc/warp-route-before.txt`);
- откат, если default route изменился;
- откат, если `ssh`/`sshd` перестал быть active.

Режим **TUN / full-tunnel** в UI и API заблокирован.

## Взаимоисключение с Tor

```bash
olc-feature tor on    # ошибка, если WARP включён
olc-feature warp on   # ошибка, если Tor включён
```

Переключение: сначала `off` одного слоя, затем `on` другого.

## Панель `/admin`

- Переключатель **WARP** в шапке и в «Сеть и обход» (виден всегда, даже до установки).
- Настройки: proxy endpoint, autoconnect, WARP+, license key.
- Установка/удаление через drawer **«Компоненты VPS»** (±) — job с логом и статусом после F5.

Переменные в `/etc/olcrtc-manager/panel.env`:

| Ключ | По умолчанию |
|------|----------------|
| `OLCRTC_WARP_PROXY` | `127.0.0.1:40000` |
| `OLCRTC_WARP_MODE` | `proxy` |
| `OLCRTC_WARP_AUTOCONNECT` | `1` |
| `OLCRTC_ENABLE_WARP` | `0` / `1` в `features.env` |

## CLI

```bash
olc-feature warp status
olc-feature warp on
olc-feature warp off
```

## API (manager)

- `GET /api/settings/warp` — настройки (без license в ответе при необходимости маскировки)
- `POST /api/settings/warp` — сохранение
- `GET /api/components/jobs` — активные/завершённые jobs установки компонентов

См. также [FEATURES.md](FEATURES.md), [SECURITY-NETWORK.md](SECURITY-NETWORK.md).
