# Olc-cost-l — быстрый старт (для новичков)

Репозиторий: [Olc-cost-l](https://github.com/krygag1234-a11y/Olc-cost-l)

## Что вы получите

- Панель **OlcRTC Manager** на порту **8888** (`/admin`)
- Туннель **olcrtc** к Jitsi / Telemost / WB Stream
- На RU VPS: **Tor**, **split** (RU direct), **zapret**, **мосты**

## 1. Установка (одна команда)

> **Для новичков:** Используйте команду со стабильной версией панели!

На чистом Ubuntu/Debian VPS от root:

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --manager-stable
```

Если панель должна быть доступна только через SSH-туннель:

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --manager-stable --ssh
```

<details>
<summary>📖 Что означает --manager-stable?</summary>

- **`--manager-stable`** (рекомендуется) — проверенная стабильная версия панели из нашего форка
- **`--manager-latest`** — самая новая версия из upstream (может сломаться)
- **без флага** — pinned версия из репозитория (средний вариант)

</details>

Перед установкой (рекомендуется):

```bash
sudo apt-get update && sudo apt-get install -y curl git
# проверка места на диске:
curl -fsSL .../install.sh | sudo bash -s -- --state  # не ставит, только проверки
sudo olc-disk-check   # после первого клона репо
```

## 2. Открыть панель

В обычном режиме: `http://IP_ВАШЕГО_VPS:8888/admin`

В режиме `--ssh` сначала откройте туннель со своего компьютера/ноутбука, а не внутри VPS:

```bash
ssh -L 8888:127.0.0.1:8888 root@IP_ВАШЕГО_VPS
```

Пока SSH-подключение открыто, в браузере на этом же устройстве откройте: `http://127.0.0.1:8888/admin`

При первом входе задайте логин и пароль администратора.

## 3. Создать клиента и инстанс

1. **Клиенты** → «Создать клиента»
2. Укажите провайдер (Jitsi, Telemost, WB Stream…)
3. Room ID — для Jitsi ссылка meet, для Telemost — ID комнаты
4. **QR** — ссылка для Olcbox на телефоне/ПК

## 4. Обновление и доустановка

> **Для новичков:** Обновляйте стабильной версией панели!

Вы можете обновить скрипты, панель и патчи короткой командой (если репозиторий уже склонирован на сервер):

```bash
sudo olc-update --manager-stable
```

Если установка была сделана с `--ssh`, `olc-update` сохранит localhost-режим автоматически. Явно переключить режим можно так:

```bash
sudo olc-update --manager-stable --ssh  # панель только через SSH-туннель
sudo olc-update --manager-stable --ip   # обычный открытый режим на IP
```

Или через curl (если сервер свежий или команда `olc-update` недоступна):

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --update --manager-stable
```

<details>
<summary>⚙️ Другие варианты обновления (для продвинутых)</summary>

```bash
# Обновиться на последнюю upstream версию (экспериментальная)
sudo olc-update --manager-latest

# Обновиться на pinned версию из репозитория
sudo olc-update
```

</details>

Только пересобрать панель из эталона (без полного update):

```bash
sudo olc-panel-refresh-local.sh
```

## 5. Полезные команды

| Команда | Зачем |
|---------|--------|
| `sudo olc-feature tor on/off` | Tor |
| `sudo olc-feature warp on/off` | WARP (обычно foreign VPS) |
| `sudo olc-disk-check` | Место на диске |
| `sudo olc-panel-verify` | Совпадает ли сборка с эталоном |
| `sudo olc-vps-snapshot` | Снимок конфига VPS в репо |

## 6. Режимы установки

| Флаг | Когда |
|------|--------|
| (без флагов) | RU VPS: Tor + split + zapret |
| `--no-tor` | Иностранный VPS, без Tor |
| `--with-warp` | Foreign + Cloudflare WARP |
| `--update` | Только обновить уже установленное |

## 7. Если что-то сломалось

- **Панель белая / «Ошибка панели» (React #300)** — обновите панель: `sudo olc-panel-refresh-local.sh` или `install.sh --update`, затем Ctrl+F5
- **Нет места на диске** — `sudo olc-disk-check`, очистить `/var/backups/olc-vps/`, кэши
- **Tor не работает при включённом WARP** — `sudo olc-feature warp off`
- **Не создаётся локация** — проверьте Room ID (для Telemost — не URL, а ID)
- **Дефолты инстансов** — «Настройки OlcRTC» → «Настройки инстансов по умолчанию…»; хранятся в `/var/lib/olcrtc/instance-defaults.json`
- **Мосты: пул обновился, в конфиге только obfs4** — нужен полный цикл pool (не только fetch). В панели: «Настройки → Мосты → Обновить сейчас»; вручную: `sudo FETCH_MAX_AGE_SEC=0 BRIDGE_TYPES=obfs4,webtunnel bash /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --types obfs4,webtunnel`. В `/etc/tor/bridges.conf` должны быть строки `Bridge webtunnel` и `ClientTransportPlugin webtunnel`.

Подробнее: [VPS-SETUP.md](VPS-SETUP.md), [FEATURES.md](FEATURES.md)
