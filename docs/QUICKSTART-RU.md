# Olc-cost-l — быстрый старт (для новичков)

Репозиторий: [Olc-cost-l](https://github.com/krygag1234-a11y/Olc-cost-l)

## Что вы получите

- Панель **OlcRTC Manager** на порту **8888** (`/admin`)
- Туннель **olcrtc** к Jitsi / Telemost / WB Stream
- На RU VPS: **Tor**, **split** (RU direct), **zapret**, **мосты**

## 1. Установка (два способа, оба с красивым TUI)

На чистом Ubuntu/Debian VPS от root.

**🅰️ С интерактивным меню (основная команда, без флагов)** — установщик спросит
конфигурацию (доступ к панели, компоненты), затем покажет полноэкранный TUI:

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
```

**🅱️ Без меню (`--full`)** — тот же TUI. Учтите: каждый флаг пропускает только
свой выбор, поэтому `--full` (компоненты заданы) всё равно спросит режим доступа
IP/SSH. Полностью без вопросов — добавьте `--ip` или `--ssh`:

```bash
# --full ещё спросит IP/SSH:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full

# без вопросов совсем (панель по IP):
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --ip
```

Панель только через SSH-туннель:

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --full --ssh
```

> Нужно меню выбора компонентов даже с флагами — добавьте `--interactive`.

<details>
<summary>📖 О версиях панели</summary>

По умолчанию устанавливается **стабильная версия панели** из нашего форка — это рекомендуется для всех.

Флаг `--manager-latest` устанавливает последнюю upstream версию (экспериментальная, может сломаться). **Не используйте для production.**

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

Вы можете обновить скрипты, панель и патчи короткой командой (если репозиторий уже склонирован на сервер):

```bash
sudo olc-update
```

Если установка была сделана с `--ssh`, `olc-update` сохранит localhost-режим автоматически. Явно переключить режим можно так:

```bash
sudo olc-update --ssh  # панель только через SSH-туннель
sudo olc-update --ip   # обычный открытый режим на IP
```

Или через curl (если сервер свежий или команда `olc-update` недоступна):

```bash
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --update
```

<details>
<summary>⚙️ Другие опции обновления</summary>

```bash
# Обновиться на последнюю upstream версию (экспериментальная, не рекомендуется)
sudo olc-update --manager-latest

# Показать текущий профиль установки
sudo olc-update --show-profile

# Продолжить прерванное обновление
sudo olc-update --resume
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

> **💡 Рекомендация:** Добавляйте `` ко всем командам для установки проверенной версии панели.

### Полный список флагов

| Флаг | Результат |
|------|-----------|
| **ВЕРСИЯ ПАНЕЛИ** | |
| `` | Стабильная проверенная версия панели (рекомендуется) |
| `--manager-latest` | Последняя версия из upstream (экспериментальная) |
| без флага | Pinned версия из репозитория (средний вариант) |
| **ПОЛНАЯ УСТАНОВКА** | |
| `--full` | Панель + Tor + мосты + split + zapret |
| `--full --no-tor` | Всё, кроме Tor/мостов (foreign VPS) |
| `--full --no-split` | Без разделения: весь трафик через Tor |
| `--full --no-zapret` | Без DPI-обхода |
| `--full --no-bridges` | Без мостов (только прямой Tor) |
| **ОТДЕЛЬНЫЕ КОМПОНЕНТЫ** | |
| `--tor` | Только Tor + панель |
| `--bridges` | Только мосты + панель (требует Tor) |
| `--split` | Только split + панель (требует Tor) |
| `--zapret` | Только zapret + панель |
| `--warp` | Cloudflare WARP proxy + панель (без Tor) |
| **ОБНОВЛЕНИЕ** | |
| `--update` | Git pull + пересборка + обновление списков |
| `--incremental` | Доустановка недостающих компонентов (без полной пересборки) |
| `--resume` | Продолжить прерванную установку с последнего шага |
| **ДОСТУП К ПАНЕЛИ** | |
| `--ssh` | Панель только через SSH-туннель (127.0.0.1) |
| `--ip` | Вернуть открытый режим панели на IP |
| **ДРУГОЕ** | |
| `--force-sha-update` | Автообновление SHA256 checksums при несовпадении |

Флаги можно комбинировать! Например: `--tor --bridges --zapret`

## 7. Если что-то сломалось

- **Панель белая / «Ошибка панели» (React #300)** — обновите панель: `sudo olc-panel-refresh-local.sh` или `install.sh --update`, затем Ctrl+F5
- **Нет места на диске** — `sudo olc-disk-check`, очистить `/var/backups/olc-vps/`, кэши
- **Tor не работает при включённом WARP** — `sudo olc-feature warp off`
- **Не создаётся локация** — проверьте Room ID (для Telemost — не URL, а ID)
- **Дефолты инстансов** — «Настройки OlcRTC» → «Настройки инстансов по умолчанию…»; хранятся в `/var/lib/olcrtc/instance-defaults.json`
- **Мосты: пул обновился, в конфиге только obfs4** — нужен полный цикл pool (не только fetch). В панели: «Настройки → Мосты → Обновить сейчас»; вручную: `sudo FETCH_MAX_AGE_SEC=0 BRIDGE_TYPES=obfs4,webtunnel bash /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --types obfs4,webtunnel`. В `/etc/tor/bridges.conf` должны быть строки `Bridge webtunnel` и `ClientTransportPlugin webtunnel`.

Подробнее: [VPS-SETUP.md](VPS-SETUP.md), [FEATURES.md](FEATURES.md)
