# Olc-cost-l

Скрипты и патчи для **olcrtc-manager-panel** + **olcrtc** ([ветка `refactor/universal-carrier`](https://github.com/openlibrecommunity/olcrtc/tree/refactor/universal-carrier)) на VPS.

Рабочий carrier: **Jitsi** (datachannel). WB Stream / Telemost в upstream нестабильны.

Клиент: [Olcbox nightly-universal-carrier](https://github.com/alananisimov/olcbox/releases/tag/nightly-universal-carrier).

---

## Быстрая установка

```bash
# RU VPS: Tor + split (RU напрямую, остальное через Tor) + патчи
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash

# Иностранный VPS — без Tor
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --no-tor

# Уже клонировали репо
git clone https://github.com/krygag1234-a11y/Olc-cost-l.git /opt/Olc-cost-l
cd /opt/Olc-cost-l && chmod +x scripts/*.sh install.sh
sudo OLC_REPO_ROOT=/opt/Olc-cost-l ./scripts/agent-bootstrap.sh --full
```

Панель: `http://ВАШ_IP_ИЛИ_DDNS:8888/admin` — при первом входе задайте пароль.

---

## Что внутри

| Каталог | Содержимое |
|---------|------------|
| `scripts/` | Установка, Tor pool, healthcheck, RU CIDR |
| `patches/` | Патчи к upstream olcrtc + manager ([PATCHES.md](patches/PATCHES.md)) |
| `packaging/systemd/` | Примеры unit/timer |
| [docs/VPS-SETUP.md](docs/VPS-SETUP.md) | Полная документация |
| [docs/SAFETY.md](docs/SAFETY.md) | Что трогают скрипты, откат |

---

## Режимы установки

| Команда | Когда |
|---------|--------|
| `agent-bootstrap.sh --full` | Чистый VPS |
| `agent-bootstrap.sh --full --no-tor` | VPS за границей, Tor не нужен |
| `agent-bootstrap.sh --no-split` | Tor без RU direct |
| `agent-bootstrap.sh --rebuild-only` | Только пересборка патченных бинарников |

---

## Отличия от «голого» upstream

- Логи в панели: `/api/logs?client_id=...`
- Jitsi: увеличенный datachannel payload, мягкий liveness
- `OLCRTC_HOST_NETWORK=1` — без netns (проще на VPS)
- Tor exit только если SOCKS жив (Jitsi не падает при мёртвом Tor)
- Split: RU IP → direct, остальное → Tor
- Пул мостов из [TOR_BRIDGES_ALL.txt](https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/TOR-BRIDGES/TOR_BRIDGES_ALL.txt) без комментариев в torrc
- DDNS: `OLCRTC_PUBLIC_URL` для подписок Olcbox

**Ветка olcrtc — не `main`.** Документация upstream может не совпадать с кодом.

---

## Tor bridges

```bash
/opt/Olc-cost-l/scripts/tor-bridge-pool.sh --fetch --url-only --target 12
/opt/Olc-cost-l/scripts/tor-bridge-monitor.sh   # health, без рестарта
```

Мосты с [bridges.torproject.org](https://bridges.torproject.org) (капча) — **не автоматизируем**.

---

## DDNS (динамический IP VPS)

В Olcbox: `http://ваш-домен:8888/<client_id>/`  
В `/etc/olcrtc-manager/panel.env`: `OLCRTC_PUBLIC_URL=http://ваш-домен:8888`

---

## Безопасность

Скрипты пишут только в allowlist путей, делают `.bak.*` перед заменой `bridges.conf`, не трогают SSH и маршрутизацию хоста. Подробно: [docs/SAFETY.md](docs/SAFETY.md).

---

## Лицензии upstream

- [olcrtc](https://github.com/openlibrecommunity/olcrtc) — WTFPL  
- [olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel)  
- Патчи и скрипты в этом репозитории — как есть, на свой риск
