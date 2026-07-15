# Установка и обновление

## Одна команда (с GitHub)

> **Рекомендуется:** Используйте стабильную версию панели!

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full
```

| Состояние VPS | Действие |
|---------------|----------|
| `fresh` | `agent-bootstrap.sh --full` |
| `installed` / `partial` | `agent-bootstrap.sh --update` |

Симлинк: `/opt/olcrtc` → `/opt/Olc-cost-l`

### Версии панели

- **По умолчанию** (рекомендуется): Стабильный форк с проверенными патчами из https://github.com/krygag1234-a11y/local-panel-version
- **`--manager-latest`**: HEAD из upstream (экспериментальная, может сломаться при обновлении)

> ℹ️ С версии `d92baf4` стабильный форк используется по умолчанию (`OLC_MANAGER_STABLE=1`). Флаг больше не нужен.

## После клонирования репозитория

```bash
sudo olc-update       # git pull + bootstrap по deploy-profile
sudo olc-update --show-profile
sudo olc-update --profile ru-full

sudo olc-feature status                # toggle без переустановки пакетов
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --rebuild-only
```

`olc-update` вызывает `scripts/agent-bootstrap.sh --update` с учётом `/etc/olcrtc-manager/deploy-profile.json` (инкрементальный update: foreign VPS не тянет лишний zapret/Tor).

## Ручные режимы install.sh

```bash
# Рекомендуемая полная установка
sudo bash install.sh --full

# Обновление стабильной версии
sudo bash install.sh --update

# Продолжить прерванную установку
sudo bash install.sh --resume

# Ручные варианты из репозитория
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --full --no-tor
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --with-warp   # foreign + WARP
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
3. Клонирование/обновление панели согласно флагу (`` / `--manager-latest` / pinned)
4. Шаги по **deploy-profile**: split-списки, Tor pool, zapret, timers
5. `features.env` — после update **не** включает выключенные компоненты
6. `systemctl restart olcrtc-manager`

`torrc` и существующий `bridges.conf` не сносятся; пул дополняется.

### Автообновление SHA256 checksums

Если при обновлении `golden-panel` checksum не совпадает:

```bash
# Автоматически обновить checksum без запроса
sudo olc-update --force-sha-update
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

См. [FEATURES.md](./FEATURES.md), [RESUME-INSTALL.md](./RESUME-INSTALL.md).
