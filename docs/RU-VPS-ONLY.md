# Только RU VPS (split, мосты, CDN)

Скрипты **split** (RU CIDR, CDN, плееры), **Tor bridges**, `setup-split-ru.sh` — рассчитаны на **VPS в России** с Tor.

## Установка

```bash
# RU VPS (по умолчанию)
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash

# Явно RU
sudo ./scripts/agent-bootstrap.sh --full --ru
```

## Иностранный VPS (без split, без мостов)

```bash
curl -fsSL .../install.sh | sudo bash -s -- --no-tor
# или
sudo ./scripts/agent-bootstrap.sh --full --foreign
```

Не запускаются: `fetch-ru-cidrs.sh`, `fetch-cdn-direct.sh`, `fetch-ru-player-cdn.sh`, `setup-split-ru.sh`, timers мостов (если отключён Tor).

## Обновить списки direct (RU VPS)

```bash
sudo /opt/Olc-cost-l/scripts/setup-split-ru.sh
sudo systemctl restart olcrtc-manager
```

Файлы:

| Файл | Содержимое |
|------|------------|
| `/var/lib/olcrtc/ru-cidrs.txt` | RU CIDR |
| `/var/lib/olcrtc/cdn-direct.txt` | глобальные CDN |
| `/var/lib/olcrtc/ru-player-cdn.txt` | Okko, IVI, Kinopoisk, Rutube, VK Video… |
| `/var/lib/olcrtc/direct-all.txt` | merge → `OLCRTC_DIRECT_CIDRS` |

Дополнить домены плеера: правьте `scripts/fetch-ru-player-cdn.sh` → `HOSTS=(...)`.

## Nodе / multi-region

Не поддерживается. Отдельные foreign-ноды — позже.
