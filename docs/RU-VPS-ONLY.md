# Только RU VPS (split, мосты, CDN)

Скрипты **split** (RU CIDR, CDN, плееры), **Tor bridges**, `setup-split-ru.sh` — рассчитаны на **VPS в России** с Tor.

## Установка

```bash
# RU VPS (рекомендуемая, стабильная панель)
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --manager-stable

# Явно RU
sudo ./scripts/agent-bootstrap.sh --full --ru --manager-stable
```

## Иностранный VPS (без split, без мостов)

```bash
curl -fsSL .../install.sh | sudo bash -s -- --full --no-tor --manager-stable
# или
sudo ./scripts/agent-bootstrap.sh --full --foreign --manager-stable
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
| `/var/lib/olcrtc/ru-cidrs.txt` | GeoIP RU (CIDR) |
| `/var/lib/olcrtc/ru-direct-domains.txt` | **Домены** `.ru`, Okko, IVI, Rutube… (основной фикс плееров) |
| `OLCRTC_DIRECT_DOMAINS` | в `panel.env` |

CDN /32 (`cdn-direct`, `ru-player-cdn`) **отключены** по умолчанию — давали 404 nginx.  
Дополнить домены: `scripts/fetch-ru-direct-domains.sh`.

## Nodе / multi-region

Не поддерживается. Отдельные foreign-ноды — позже.
