# Olc-cost-l

Скрипты и патчи для **olcrtc-manager-panel** + **olcrtc** на RU/foreign VPS: Tor, Tor-мосты, split-маршрутизация, zapret, Warp. Olcbox.

<img src="https://github.com/krygag1234-a11y/Olc-cost-l/blob/main/%D1%8C.jpg" width="300" alt="Image alt">

## Upstream (2026-05)

| Компонент | Ветка / источник | Ссылка |
|-----------|------------------|--------|
| olcrtc | **`fix/all`** (pin в `data/upstream-pins.json`) | https://github.com/openlibrecommunity/olcrtc/tree/fix/all |
| manager panel | **`main`** + патчи в `scripts/patch-olcrtc-manager-*.sh` | https://github.com/BigDaddy3334/olcrtc-manager-panel |
| webtunnel-client | **mirror-cry** (prebuilt) | https://github.com/krygag1234-a11y/mirror-cry/releases |
| Olcbox | **`nightly`** | https://github.com/alananisimov/olcbox/releases/tag/nightly |

Olcbox: [releases](https://github.com/alananisimov/olcbox/releases) · [CLIENT.md](docs/CLIENT.md)

---

## Быстрая установка

```bash
# Быстрая установка одной командой (устанавливает всё: Tor, Split, Zapret, мосты и исправления панели)
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full
```

---

## Примеры выборочных команд со флагами вида "ВСЕ, НО БЕЗ .."

```bash
# Иностранный VPS (без Tor и мостов):
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --no-tor

# RU VPS (без разделения маршрутов, весь трафик через Tor):
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --no-split

# RU VPS (без Zapret DPI обхода):
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --no-zapret
```

---

## Примеры выборочных команд со флагами вида "ТОЛЬКО С .."

```bash
# Иностранный VPS + Cloudflare WARP (proxy, без Tor):
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --warp

# Установить только Tor + Панель:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --tor

# Установить только Zapret + Панель:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --zapret
```

## Команды обновления

```bash
# Обновление или доустановка:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --update
```

> **Или короткая команда** (если репозиторий уже установлен):
> ```bash
> sudo olc-update
> ```

## Режимы bootstrap (установки)

Флаги можно комбинировать! Например, `--bridges --zapret` установит панель только с мостами и запретом. Или `--full --no-bridges --no-zapret` установит всё, но без мостов и запрета. Неправильные конфигурации (например, `--full --split`) будут отклонены скриптом с понятной ошибкой.

| Флаг | Результат |
|------|-----------|
| **ВСЕ, НО БЕЗ ..** | |
| `--full` | **Полная установка:** Панель + исправления + Tor + мосты + split + zapret |
| `--full --no-tor` | Устанавливает всё, кроме Tor и мостов |
| `--full --no-split` | Без разделения: весь трафик идёт через Tor |
| `--full --no-zapret` | Без DPI-обхода (zapret не устанавливается) |
| `--full --no-bridges`| Без мостов для Tor (только прямой Tor) |
| **ТОЛЬКО С ..** | |
| `--warp` | Устанавливается только WARP + панель (без Tor) |
| `--tor` | Устанавливается только Tor + панель |
| `--split` | Устанавливается только Split + панель (требует Tor) |
| `--zapret` | Устанавливается только Zapret + панель |
| `--bridges`| Устанавливается только мосты для Tor + панель |
| **ДРУГОЕ** | |
| `--update` | Обновление: git pull, пересборка, обновление списков и служб или доустановка |

Панель: `http://ВАШ_IP_ИЛИ_DDNS:8888/admin` · [QUICKSTART-RU.md](docs/QUICKSTART-RU.md) · [UPDATE.md](docs/UPDATE.md)

## Полное удаление

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/uninstall.sh | sudo bash
curl -fsSL .../uninstall.sh | sudo bash -s -- --purge-repo   # + удалить /opt/Olc-cost-l
curl -fsSL .../uninstall.sh | sudo bash -s -- --keep-tor     # оставить tor@default
```

> **Или короткая команда** (если репозиторий уже установлен):
> ```bash
> sudo olc-purge
> ```

---

## Roadmap

Мастер-план задач (настройки Zp/Tor/Split/Мосты, update из UI, уведомления, баги): **[docs/ROADMAP.md](docs/ROADMAP.md)**.

## Документация

| Документ | Тема |
|----------|------|
| [VPS-SETUP.md](docs/VPS-SETUP.md) | Полная установка, таймеры, troubleshooting |
| [TOR-BRIDGES.md](docs/TOR-BRIDGES.md) | Пул, ротация, deep check, snowflake |
| [PERFORMANCE.md](docs/PERFORMANCE.md) | Потолок Tor, параллельные потоки vs WebRTC |
| [SPLIT-ROUTING.md](docs/SPLIT-ROUTING.md) | Direct vs Tor по доменам |
| [RU-BLOCKED-TOR.md](docs/RU-BLOCKED-TOR.md) | Заблокированные `.ru` + zapret |
| [ZAPRET-OPTIONAL.md](docs/ZAPRET-OPTIONAL.md) | Zapret на VPS |
| [SECURITY-NETWORK.md](docs/SECURITY-NETWORK.md) | SOCKS, авторизация |
| [SAFETY.md](docs/SAFETY.md) | Allowlist путей, откат |
| [CLIENT.md](docs/CLIENT.md) | Olcbox |
| [patches/PATCHES.md](patches/PATCHES.md) | Патчи olcrtc / manager |
| [INTEGRATION-GAP.md](docs/INTEGRATION-GAP.md) | Отличия Olc-cost-l от upstream |
| [PUBLIC-DEMO-VPS.md](docs/PUBLIC-DEMO-VPS.md) | Общедоступный VPS: что не хранить на хосте |
| [UPSTREAM-SYNC.md](docs/UPSTREAM-SYNC.md) | Обновление upstream + zapret4rocket |
| [FEATURES.md](docs/FEATURES.md) | `olc-feature` — toggle zapret/tor/split/webtunnel/warp |
| [WARP-OPTIONAL.md](docs/WARP-OPTIONAL.md) | Cloudflare WARP (proxy mode, foreign VPS) |
| [RESUME-INSTALL.md](docs/RESUME-INSTALL.md) | Resumable install/update + webtunnel mirror |

---

## Tor — основные команды

```bash
# Обновить пул (все источники)
sudo /opt/Olc-cost-l/scripts/fetch-bridge-extra-sources.sh

# Применить лучшие мосты + restart Tor
sudo BRIDGE_TYPES=webtunnel,obfs4 /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --apply

# Deep bootstrap (реальный tor на каждый мост)
sudo /opt/Olc-cost-l/scripts/tor-bridge-deep-check.sh --from-pool --limit 10 --jobs 2

# Быстрая ротация без скачивания
sudo /opt/Olc-cost-l/scripts/tor-bridge-rotate.sh
```

Таймеры: `olcrtc-tor-bridge-pool.timer`, `olcrtc-tor-bridge-monitor.timer`, `olcrtc-tor-bridge-deep.timer`

---

## Отличия от upstream panel

- API логов, HOST_NETWORK, EXIT_PROXY при живом Tor
- Split: `*.ru` + CDN direct; blocked `.ru` + zapret; YouTube → Tor
- Bridge pool: multi-source, webtunnel-first, health + deep bootstrap
- Healthcheck по `/admin` (не `/`)

---

## Upstream sync

```bash
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --check
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --apply
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --check
```

См. [UPSTREAM-SYNC.md](docs/UPSTREAM-SYNC.md)

---

`OLCRTC_PUBLIC_URL=http://ваш-домен:8888` в `/etc/olcrtc-manager/panel.env`
