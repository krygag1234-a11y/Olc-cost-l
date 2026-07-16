# 🎨 TUI Library

Интерактивная библиотека Terminal UI для установщика Olc-cost-l.

## Две команды установки — обе с полноэкранным TUI

| Команда | Меню выбора | TUI-прогресс |
|---|---|---|
| `curl … \| sudo bash` (без флагов) | ✅ интерактивное меню компонентов/доступа | ✅ |
| `curl … \| sudo bash -s -- --full [--ssh/--ip/…]` | ❌ (полная конфигурация без вопросов) | ✅ |
| `curl … \| sudo bash -s -- --full --interactive` | ✅ (меню даже с флагами) | ✅ |

- **Без флагов** = основная интерактивная команда: `install.sh` показывает
  `interactive_install_menu` (режим доступа + набор компонентов) на чистой системе,
  либо меню действий (`tui_menu`), если система уже установлена. Выбор меню
  транслируется в `--no-*`/`--ssh` флаги для `agent-bootstrap.sh`.
- **С флагами** (`--full`, `--tor`, `--warp`, `--no-zapret`, `--ssh`, …) меню
  пропускается, но полноэкранный TUI (шапка, бар N/13, `^O`, финальная анимация,
  сводки) остаётся. Конфликтующие флаги отклоняются `tui_fatal`.
- Проверка парсинга всех флагов без реальной установки: `--plan` (dry-run) в
  `install.sh`, `olc-update.sh`, `agent-bootstrap.sh`; регрессия —
  `scripts/test-install-flags.sh`.

## Возможности

✓ **Цвета и градиенты** - 16 цветов для логов  
✓ **Анимированные спиннеры** - 4 стиля (dots, line, arc, arrows)  
✓ **Progress bar** - с процентами и анимацией  
✓ **Интерактивное меню** - навигация стрелками  
✓ **Логи** - info, success, warning, error, step, bullet  
✓ **Box drawing** - рамки для текста  

## Использование

```bash
source scripts/lib-tui.sh

# Spinner
tui_spinner_start "Установка зависимостей"
apt-get install -y some-package
tui_spinner_ok

# Progress bar
tui_progress_bar 50 100

# Menu
choice=$(tui_menu "Выберите:" "Установить" "Обновить" "Отмена")
```

## Demo

```bash
bash scripts/demo-tui.sh
```

## Функции

### Цвета
- `TUI_RED`, `TUI_GREEN`, `TUI_YELLOW`, `TUI_BLUE`, `TUI_MAGENTA`, `TUI_CYAN`
- `TUI_BOLD`, `TUI_DIM`, `TUI_RESET`

### Spinners
- `tui_spinner_start "message"` - запуск spinner
- `tui_spinner_ok` - успешное завершение (✓)
- `tui_spinner_fail` - ошибка (✗)

### Progress Bar
- `tui_progress_bar <current> <total>` - отрисовка progress bar

### Меню
- `tui_menu "prompt" "option1" "option2" ...` - интерактивное меню

### Логи
- `tui_log_info "message"` - информация (ℹ)
- `tui_log_success "message"` - успех (✓)
- `tui_log_warning "message"` - предупреждение (⚠)
- `tui_log_error "message"` - ошибка (✗)
- `tui_log_step "message"` - шаг установки (→)

### Box Drawing
- `tui_box "title" "content"` - рамка вокруг текста
