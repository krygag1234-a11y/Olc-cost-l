# Olc-cost-l

Скрипты и патчи для **olcrtc-manager-panel** + **olcrtc** на VPS (RU/foreign).

## Upstream (актуально 2026-05)

| Компонент | Ветка | Ссылка |
|-----------|--------|--------|
| olcrtc | **`master`** | https://github.com/openlibrecommunity/olcrtc |
| manager panel | **`main`** | https://github.com/BigDaddy3334/olcrtc-manager-panel |
| Olcbox клиент | **`nightly`** | https://github.com/alananisimov/olcbox/releases/tag/nightly |

`refactor/universal-carrier` **смержена в master** ([merge 85faadd](https://github.com/openlibrecommunity/olcrtc/commit/85faadd)).  
Upstream install.sh панели уже ставит `OLCRTC_REF=master` ([коммит 6878fc8](https://github.com/BigDaddy3334/olcrtc-manager-panel/commits/main/)).

**Не используйте** голый `curl …/olcrtc-manager-panel/…/install.sh` на этом VPS — он без Tor/split/патчей. Только этот репо.

### Olcbox — ссылки для пользователей

- Стабильная (не ломается при смене тега): https://github.com/alananisimov/olcbox/releases  
- Репозиторий: https://github.com/alananisimov/olcbox  
- Конкретный nightly: https://github.com/alananisimov/olcbox/releases/tag/nightly  

Подробнее: [docs/CLIENT.md](docs/CLIENT.md)

---

## Быстрая установка

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
# Иностранный VPS:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --no-tor
```

Панель: `http://ВАШ_IP_ИЛИ_DDNS:8888/admin`

---

## Что внутри

| Каталог | Содержимое |
|---------|------------|
| `scripts/` | bootstrap, патчи, Tor pool, RU/CDN direct |
| `patches/` | olcrtc + manager ([PATCHES.md](patches/PATCHES.md)) |
| [docs/VPS-SETUP.md](docs/VPS-SETUP.md) | Полная установка |
| [docs/TOR-BRIDGES.md](docs/TOR-BRIDGES.md) | Мосты, скорость failover |
| [docs/CLIENT.md](docs/CLIENT.md) | Olcbox |
| [docs/SAFETY.md](docs/SAFETY.md) | Откат |
| [docs/SECURITY-NETWORK.md](docs/SECURITY-NETWORK.md) | SOCKS/Tor/авторизация |
| [docs/RU-VPS-ONLY.md](docs/RU-VPS-ONLY.md) | Split только на RU VPS |

---

## Режимы (`agent-bootstrap.sh`)

| Флаг | Результат |
|------|-----------|
| `--full` | Tor + split RU/CDN + патчи |
| `--full --no-tor` / `--foreign` | Иностранный VPS: панель + olcrtc, **без Tor/split/мостов** |
| `--no-split` | RU VPS: Tor на всё, без списков direct |
| `--ru` | Явно RU: Tor + split (RU+CDN+плееры) |
| `--rebuild-only` | Пересборка бинарников |

В `config.json` поле **`link`**: для подписок Olcbox (`tor` / `direct`). **Tor exit на сервере** включается через `OLCRTC_EXIT_PROXY` в systemd — все location получают SOCKS + split (RU/CDN direct, остальное через Tor). Отключить Tor на всём VPS: `--no-tor`.

---

## Отличия от upstream panel

- `/api/logs?client_id=` (без trailing slash)
- `OLCRTC_HOST_NETWORK=1` — host network + Tor `127.0.0.1:9050`
- SOCKS + split для всех location, если Tor жив (`OLCRTC_EXIT_PROXY`)
- Split: RU + CDN direct, остальное Tor
- Bridge pool с fast rotate ([TOR-BRIDGES.md](docs/TOR-BRIDGES.md))

---

## Tor bridges

```bash
/opt/Olc-cost-l/scripts/tor-bridge-pool.sh --fetch --url-only --target 12
/opt/Olc-cost-l/scripts/tor-bridge-monitor.sh   # timer: fast rotate если Tor down
```

---

## DDNS

`OLCRTC_PUBLIC_URL=http://ваш-домен:8888` в `/etc/olcrtc-manager/panel.env`

---

## Секреты

GitHub PAT / API-ключи **не хранятся** в репозитории. Если ключ светился в чате — **отозвать** в GitHub Settings → Developer settings.
