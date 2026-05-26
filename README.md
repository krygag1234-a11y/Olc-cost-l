# Olc-cost-l

# сорре, пока еще хуйня

Скрипты и патчи для **olcrtc-manager-panel** + **olcrtc** на RU/foreign VPS: Tor-мосты, split-маршрутизация, zapret, Olcbox.

**Репозиторий:** https://github.com/krygag1234-a11y/Olc-cost-l

## Upstream (2026-05)

| Компонент | Ветка | Ссылка |
|-----------|--------|--------|
| olcrtc | **`master`** | https://github.com/openlibrecommunity/olcrtc |
| manager panel | **`main`** | https://github.com/BigDaddy3334/olcrtc-manager-panel |
| Olcbox | **`nightly`** | https://github.com/alananisimov/olcbox/releases/tag/nightly |

**Не используйте** голый `install.sh` панели — без Tor, split и патчей. Только этот репо.

Olcbox: [releases](https://github.com/alananisimov/olcbox/releases) · [CLIENT.md](docs/CLIENT.md)

---

## Быстрая установка

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
# Иностранный VPS (без Tor):
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --no-tor
# Только обновление:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --update
```

Панель: `http://ВАШ_IP_ИЛИ_DDNS:8888/admin` · [UPDATE.md](docs/UPDATE.md)

## Полное удаление

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/uninstall.sh | sudo bash
curl -fsSL .../uninstall.sh | sudo bash -s -- --purge-repo   # + удалить /opt/Olc-cost-l
curl -fsSL .../uninstall.sh | sudo bash -s -- --keep-tor     # оставить tor@default
```

Из клонированного репо: `sudo bash /opt/Olc-cost-l/scripts/olc-purge.sh`

---

## Стек на RU VPS (текущее состояние)

| Слой | Что делает |
|------|------------|
| **olcrtc-manager** | Панель :8888, подписки Olcbox, `link: tor` по умолчанию |
| **olcrtc** | Туннель к Jitsi/WebRTC; split: RU/CDN direct, остальное → Tor SOCKS |
| **Tor** | `tor@default` + `bridges.conf` (webtunnel **первые**, obfs4 запас) |
| **Пул мостов** | igareck + [Tor-Bridges-Collector](https://github.com/Delta-Kronecker/Tor-Bridges-Collector) (`data/bridge-extra-urls.txt`) |
| **Мониторинг** | healthcheck */10, monitor */20, pool */6h, **deep check** раз в неделю |
| **zapret** | DPI на direct egress для заблокированных `.ru` |
| **Списки** | `*.ru`, CDN, `2ipcore`, force-tor (YouTube), geosite |

```text
Olcbox → VPS olcrtc → { direct (.ru/CDN) | SOCKS Tor → мост → exit }
```

---

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
| [UPSTREAM-AUDIT.md](docs/UPSTREAM-AUDIT.md) | Сверка Olc-cost-l с upstream olcrtc + manager |
| [UPSTREAM-OLCRTC.md](docs/UPSTREAM-OLCRTC.md) | Upstream olcrtc: carriers, обновления, WB/Telemost/Jitsi |
| [INTEGRATION-GAP.md](docs/INTEGRATION-GAP.md) | Отличия Olc-cost-l от upstream |
| [UPSTREAM-SYNC.md](docs/UPSTREAM-SYNC.md) | Обновление upstream + zapret4rocket |
| [FEATURES.md](docs/FEATURES.md) | `olc-feature` — toggle zapret/tor/split/webtunnel |
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

## Режимы bootstrap

| Флаг | Результат |
|------|-----------|
| `--full` | Tor + split + zapret + патчи |
| `--full --no-tor` | Иностранный VPS, без мостов |
| `--no-split` | Tor на весь трафик |
| `--update` | git pull, пересборка, списки, units |

В `config.json`: **`link: tor`** (по умолчанию) или **`link: direct`** (без SOCKS для этой локации).

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

я рот ебал запрета4рокет
