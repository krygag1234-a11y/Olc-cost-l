# TODO: Флаги HTTP/HTTPS и рефакторинг TUI установщика

**Дата создания:** 2026-07-02  
**Статус:** Backend готов, UI отложен до рефакторинга TUI

---

## TODO 1: Флаги установки --http / --https

**Статус:** ✅ Backend готов (HTTPS support + panel_tls в profile), UI флаги отложены

**Что уже сделано:**
- ✅ HTTPS support в packaging/golden-panel/main.go (коммит 2dbd6a0)
- ✅ PANEL_TLS переменная в agent-bootstrap.sh
- ✅ panel_tls добавлен в deploy-profile.json (коммит 14ad83d)
- ✅ Синхронизировано в local-panel-version (коммит 0966095)

**Что нужно добавить:**

### 1.1. Флаги в install.sh и agent-bootstrap.sh

```bash
# install.sh
--http)       export PANEL_TLS=0; BOOT_ARGS+=("$1") ;;
--https)      export PANEL_TLS=1; BOOT_ARGS+=("$1") ;;

# agent-bootstrap.sh
--http)       PANEL_TLS=0 ;;
--https)      PANEL_TLS=1 ;;
```

### 1.2. Обновить README.md

Добавить примеры:
```bash
# HTTP (по умолчанию)
curl -fsSL ... | sudo bash -s -- --full

# HTTPS с self-signed cert
curl -fsSL ... | sudo bash -s -- --full --https
```

### 1.3. Обновить docs/VPS-SETUP.md

Добавить секцию "Выбор HTTP/HTTPS для панели"

### 1.4. Интеграция в TUI установщик

См. TODO 2 ниже

**Текущий дефолт:** HTTP (`PANEL_TLS=0`)

**Предложенные варианты установки (для будущего TUI):**
- `--panel-access localhost` → 127.0.0.1:8888 HTTP (SSH tunnel)
- `--panel-access ip` → 0.0.0.0:8888 HTTP (текущий режим)
- `--panel-access ip-tls` → 0.0.0.0:8888 HTTPS (self-signed cert)

**Приоритет:** СРЕДНИЙ (после рефакторинга TUI установщика)

---

## TODO 2: Рефакторинг TUI установщика

**Цель:** Упростить README, вынести все флаги в docs, создать интерактивное меню

**Проблема:**
- Слишком много флагов в README (сложно для пользователя)
- Нет интерактивного выбора опций
- HTTP/HTTPS выбор не интегрирован

**План действий:**

### 2.1. Создать scripts/tui-installer.sh

Интерактивное меню с выбором:

```
┌─────────────────────────────────────────┐
│  Olc-cost-l Installer                   │
└─────────────────────────────────────────┘

Режим установки:
  1. RU VPS (полная) — рекомендуется
  2. Foreign VPS (без Tor)
  3. Foreign VPS + WARP
  4. Custom (выбрать компоненты)

Выбор [1]: _
```

### 2.2. Меню компонентов (Custom режим)

```
Компоненты (пробел = выбрать, Enter = продолжить):
  [x] Tor
  [x] Split-routing
  [x] Zapret
  [x] Bridges
  [ ] WARP
```

### 2.3. Меню panel access

```
Доступ к панели:
  1. localhost (SSH tunnel) — безопаснее
  2. IP адрес HTTP — рекомендуется
  3. IP адрес HTTPS (self-signed cert)

Выбор [2]: _
```

### 2.4. Вынести флаги в docs/INSTALL-FLAGS.md

Полная документация всех флагов:
- `--full`, `--update`, `--resume`
- `--tor`, `--split`, `--zapret`, `--bridges`, `--warp`
- `--foreign`, `--ru`
- `--ssh`, `--ip`, `--http`, `--https`
- ``, `--manager-latest`

### 2.5. Упростить README.md

Оставить только:
```bash
# Автоматическая установка (интерактивное меню)
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash

# Быстрая установка RU VPS
curl -fsSL ... | sudo bash -s -- --full

# Все опции: см. docs/INSTALL-FLAGS.md
```

**Приоритет:** ВЫСОКИЙ (после завершения синхронизации upstream)

---

## Статус выполнения

- [x] HTTPS backend support (коммит 2dbd6a0)
- [x] SOCKS auth support (коммит e6bfb00)
- [x] Peer counts UI (коммит b3d528d)
- [x] panel_tls в deploy-profile (коммит 14ad83d)
- [x] Синхронизация local-panel-version (коммит 0966095)
- [ ] Флаги --http/--https в install.sh
- [ ] TUI установщик с интерактивным меню
- [ ] Документация INSTALL-FLAGS.md
- [ ] Упрощение README.md

**Следующий шаг:** Рефакторинг патчей (группировка по функциональным областям)
