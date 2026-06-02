#!/usr/bin/env bash
# Demo script for lib-tui.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-tui.sh"

# Banner
tui_clear
tui_banner "Olc-cost-l TUI Demo"

# Log examples
tui_log_info "Информационное сообщение"
tui_log_success "Успешная операция"
tui_log_warning "Предупреждение"
tui_log_error "Ошибка"
tui_log_step "Шаг установки"
tui_log_bullet "Пункт списка"

tui_divider

# Spinner demo
tui_spinner_start "Загрузка данных"
sleep 2
tui_spinner_ok

tui_spinner_start "Проверка зависимостей"
sleep 1.5
tui_spinner_fail

# Progress bar demo
echo -e "\n${TUI_BOLD}Progress bar demo:${TUI_RESET}"
for i in {1..20}; do
  tui_progress_bar "$i" 20 50
  sleep 0.1
done

# Gradient text
echo -e "\n${TUI_BOLD}Gradient text:${TUI_RESET}"
tui_gradient "Olc-cost-l Installer v2.0"

# Box demo
echo -e "\n${TUI_BOLD}Box demo:${TUI_RESET}"
tui_box 60 "Installation Complete!"

# Confirmation
if tui_confirm "Показать интерактивное меню?"; then
  selected=$(tui_menu "Выберите действие:" \
    "Установить полностью" \
    "Обновить компоненты" \
    "Настроить Tor" \
    "Выход")
  tui_log_success "Выбрано: вариант #$selected"
fi

echo -e "\n${TUI_GREEN}Demo завершено!${TUI_RESET}\n"
