# Установка и обновление

## Одна команда (с GitHub)

> **Рекомендуется:** Используйте стабильную версию панели!

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --manager-stable
```

| Состояние VPS | Действие |
|---------------|----------|
| `fresh` | `agent-bootstrap.sh --full --manager-stable` |
| `installed` / `partial` | `agent-bootstrap.sh --update --manager-stable` |

Симлинк: `/opt/olcrtc` → `/opt/Olc-cost-l`

### Версии панели

- **`--manager-stable`** (рекомендуется): Стабильный форк с проверенными патчами из https://github.com/krygag1234-a11y/local-panel-version
- **`--manager-latest`**: HEAD из upstream BigDaddy3334 (может сломаться при обновлении)
- **без флага**: Pinned версия из `upstream-pins.json` (средний вариант)

## После клонирования репозитория

```bash
sudo olc-update --manager-stable       # git pull + bootstrap по deploy-profile
sudo olc-update --show-profile
sudo olc-update --profile ru-full --manager-stable

sudo olc-feature status                # toggle без переустановки пакетов
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --rebuild-only
```

`olc-update` вызывает `scripts/agent-bootstrap.sh --update` с учётом `/etc/olcrtc-manager/deploy-profile.json` (инкрементальный update: foreign VPS не тянет лишний zapret/Tor).

## Ручные режимы install.sh

```bash
# Рекомендуемая полная установка
sudo bash install.sh --full --manager-stable

# Обновление стабильной версии
sudo bash install.sh --update --manager-stable

# Продолжить прерванную установку
sudo bash install.sh --resume --manager-stable

# Ручные варианты из репозитория
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --full --manager-stable --no-tor
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --with-warp --manager-stable   # foreign + WARP
```

<details>
<summary>⚙️ Другие варианты версий панели</summary>

```bash
# Последняя upstream версия (экспериментальная)
sudo bash install.sh --full --manager-latest

# Pinned версия из репозитория
sudo bash install.sh --full
```

</details>

## Что делает `--update`

1. `git pull` (или `reset --hard origin/main` при грязном дереве — см. install.sh)
2. `apply-olcrtc-patches.sh` — olcrtc ветка **`master`** (pin в `data/upstream-pins.json`)
3. Клонирование/обновление панели согласно флагу (`--manager-stable` / `--manager-latest` / pinned)
4. Шаги по **deploy-profile**: split-списки, Tor pool, zapret, timers
5. `features.env` — после update **не** включает выключенные компоненты
6. `systemctl restart olcrtc-manager`

`torrc` и существующий `bridges.conf` не сносятся; пул дополняется.

### Автообновление SHA256 checksums

Если при обновлении `golden-panel` checksum не совпадает:

```bash
# Автоматически обновить checksum без запроса
sudo olc-update --manager-stable --force-sha-update
```

Флаг `--force-sha-update` работает во всех скриптах установки/обновления.

## Обновление из панели

«Состояние проекта» → обновление с GitHub. Лог: `/var/log/olcrtc-panel-update.log`, статус: `/var/lib/olcrtc/panel-update-status.json`.

### Регрессии UI/API (тестовый VPS, май 2026)

После `olc-update` должны быть доступны:

- `GET /api/project/status` (в UI больше не `HTTP 404` в «Состояние проекта»)
- `GET/PUT /api/notification-settings` (сохранение в «Звоночек → Настройки уведомлений» без `HTTP 404`)
- `GET/PUT /api/settings/warp` (без ошибки JSON `unknown component`)

Проверка с VPS:

```bash
curl -I -u admin:admin http://127.0.0.1:8888/api/project/status
curl -I -u admin:admin http://127.0.0.1:8888/api/notification-settings
curl -I -u admin:admin http://127.0.0.1:8888/api/settings/warp
```

Ожидаемо: `HTTP/1.1 200 OK` (или `401`, если без корректной авторизации).

Если job завис в `running`:

```bash
sudo bash /opt/Olc-cost-l/scripts/olc-panel-update-run.sh --reconcile
```

## Пересборка только бинарников

```bash
cd /opt/Olc-cost-l
sudo BUILD=1 bash scripts/apply-olcrtc-patches.sh
sudo systemctl restart olcrtc-manager
```

## После обновления — проверки

```bash
systemctl is-active tor@default olcrtc-manager
systemctl list-timers 'olcrtc-tor-bridge-*' --no-pager
curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
grep -cE '^Bridge ' /etc/tor/bridges.conf
```

## Tor (опционально)

```bash
sudo /opt/Olc-cost-l/scripts/fetch-bridge-extra-sources.sh
sudo /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --apply
sudo /opt/Olc-cost-l/scripts/tor-bridge-deep-check.sh --from-pool --limit 8 --jobs 2
```

## Версия стека

```bash
jq . /opt/Olc-cost-l/version.json
bash /opt/Olc-cost-l/scripts/generate-version-stack.sh   # обновить block "stack" перед релизом
```

См. [FEATURES.md](./FEATURES.md), [RESUME-INSTALL.md](./RESUME-INSTALL.md), [PUBLIC-DEMO-VPS.md](./PUBLIC-DEMO-VPS.md).
