#!/usr/bin/env bash
# Централизованная библиотека для общей логики install.sh, olc-update.sh, agent-bootstrap.sh
# Управление флагами, переменными окружения, и общими функциями

# Защита от двойного source
[[ -n "${_LIB_OLC_CORE_LOADED:-}" ]] && return 0
_LIB_OLC_CORE_LOADED=1

# === Глобальные переменные ===
# Флаги устанавливаются через parse_common_flags()
declare -g OLC_MANAGER_STABLE="${OLC_MANAGER_STABLE:-1}"
declare -g OLC_MANAGER_LATEST="${OLC_MANAGER_LATEST:-0}"
declare -g OLCRTC_FORCE_SHA_UPDATE="${OLCRTC_FORCE_SHA_UPDATE:-0}"
declare -g OLCRTC_RESUME="${OLCRTC_RESUME:-0}"
declare -g OLCRTC_FRESH="${OLCRTC_FRESH:-0}"

# === Парсинг общих флагов ===
# Используется всеми скриптами для единообразной обработки аргументов
parse_common_flags() {
  local flag="$1"
  case "$flag" in
    --manager-stable)
      export OLC_MANAGER_STABLE=1
      return 0
      ;;
    --manager-latest)
      export OLC_MANAGER_LATEST=1
      return 0
      ;;
    --force-sha-update)
      export OLCRTC_FORCE_SHA_UPDATE=1
      return 0
      ;;
    --resume)
      export OLCRTC_RESUME=1
      return 0
      ;;
    --fresh-state)
      export OLCRTC_FRESH=1
      return 0
      ;;
    *)
      return 1  # Не распознан — пусть вызывающий скрипт обработает
      ;;
  esac
}

# === Вывод статуса флагов (для отладки) ===
show_flags() {
  echo "[lib-olc-core] Текущие флаги:"
  echo "  OLC_MANAGER_STABLE=$OLC_MANAGER_STABLE"
  echo "  OLC_MANAGER_LATEST=$OLC_MANAGER_LATEST"
  echo "  OLCRTC_FORCE_SHA_UPDATE=$OLCRTC_FORCE_SHA_UPDATE"
  echo "  OLCRTC_RESUME=$OLCRTC_RESUME"
  echo "  OLCRTC_FRESH=$OLCRTC_FRESH"
}

# === Проверка версии manager ===
get_manager_install_mode() {
  if [[ "$OLC_MANAGER_STABLE" == "1" ]]; then
    echo "stable"
  elif [[ "$OLC_MANAGER_LATEST" == "1" ]]; then
    echo "latest"
  else
    echo "pinned"
  fi
}

# === Экспорт всех флагов для дочерних процессов ===
export_flags() {
  export OLC_MANAGER_STABLE
  export OLC_MANAGER_LATEST
  export OLCRTC_FORCE_SHA_UPDATE
  export OLCRTC_RESUME
  export OLCRTC_FRESH
}

# === Проверка конфликтующих флагов ===
validate_flags() {
  if [[ "$OLC_MANAGER_STABLE" == "1" && "$OLC_MANAGER_LATEST" == "1" ]]; then
    echo "ОШИБКА: нельзя использовать --manager-stable и --manager-latest одновременно" >&2
    return 1
  fi
  return 0
}

# === Обработка неизвестного флага ===
handle_unknown_flag() {
  local unknown_flag="$1"
  local script_mode="${2:-install}"  # install | update

  echo "" >&2
  echo "⚠️  ОШИБКА: Неизвестный флаг '$unknown_flag'" >&2
  echo "" >&2

  if [[ "$script_mode" == "install" ]]; then
    echo "Доступные флаги установки:" >&2
    echo "  --full              Полная установка (Tor + Split + Zapret + Панель)" >&2
    echo "  --tor               Только Tor + Панель" >&2
    echo "  --split             Только Split-routing + Панель" >&2
    echo "  --zapret            Только Zapret + Панель" >&2
    echo "  --bridges           Только мосты Tor + Панель" >&2
    echo "  --warp              Cloudflare WARP + Панель" >&2
    echo "  --manager-latest    Использовать последнюю upstream версию панели" >&2
    echo "  --ssh               Панель доступна только через SSH-туннель" >&2
    echo "" >&2
    echo "Продолжить установку с интерактивным меню? (y/N): " >&2
    read -r answer
    if [[ "${answer,,}" == "y" ]]; then
      return 0  # Продолжить с меню
    else
      echo "Установка отменена." >&2
      return 1
    fi
  elif [[ "$script_mode" == "update" ]]; then
    echo "Доступные флаги обновления:" >&2
    echo "  --manager-latest    Использовать последнюю upstream версию панели" >&2
    echo "  --force-sha-update  Принудительно обновить pinned SHA" >&2
    echo "  --resume            Продолжить прерванное обновление" >&2
    echo "  --fresh-state       Очистить состояние и начать заново" >&2
    echo "" >&2
    echo "Продолжить обновление без этого флага? (Y/n): " >&2
    read -r answer
    if [[ "${answer,,}" != "n" ]]; then
      echo "✓ Продолжаю обновление с дефолтными настройками..." >&2
      return 0
    else
      echo "Обновление отменено." >&2
      return 1
    fi
  fi
}

# === Интерактивное меню установки ===
interactive_install_menu() {
  echo ""
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║ Интерактивная установка Olc-cost-l                       ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo ""

  # 1. Выбор режима доступа к панели
  echo "1️⃣  Режим доступа к панели:"
  echo "   [1] HTTP — панель доступна по IP:8888 (рекомендуется)"
  echo "   [2] SSH  — панель только через SSH-туннель (безопаснее)"
  echo -n "Ваш выбор (1-2) [1]: "
  read -r access_mode
  access_mode="${access_mode:-1}"

  # 2. Выбор компонентов
  echo ""
  echo "2️⃣  Компоненты для установки:"
  echo "   [1] Полная установка (Tor + Split + Zapret + Мосты)"
  echo "   [2] Без Tor (только Zapret для иностранного VPS)"
  echo "   [3] Без Split (весь трафик через Tor)"
  echo "   [4] Выборочная установка (выбрать компоненты)"
  echo -n "Ваш выбор (1-4) [1]: "
  read -r components_mode
  components_mode="${components_mode:-1}"

  # 3. Выборочная установка
  local install_tor="1"
  local install_split="1"
  local install_zapret="1"
  local install_bridges="1"

  case "$components_mode" in
    1) # Полная
      install_tor="1"
      install_split="1"
      install_zapret="1"
      install_bridges="1"
      ;;
    2) # Без Tor
      install_tor="0"
      install_split="0"
      install_zapret="1"
      install_bridges="0"
      ;;
    3) # Без Split
      install_tor="1"
      install_split="0"
      install_zapret="1"
      install_bridges="1"
      ;;
    4) # Выборочная
      echo ""
      echo "Выберите компоненты для установки:"
      echo -n "  Установить Tor? (Y/n): "
      read -r ans_tor
      [[ "${ans_tor,,}" != "n" ]] && install_tor="1" || install_tor="0"

      if [[ "$install_tor" == "1" ]]; then
        echo -n "  Установить мосты Tor? (Y/n): "
        read -r ans_bridges
        [[ "${ans_bridges,,}" != "n" ]] && install_bridges="1" || install_bridges="0"

        echo -n "  Установить Split-routing? (Y/n): "
        read -r ans_split
        [[ "${ans_split,,}" != "n" ]] && install_split="1" || install_split="0"
      fi

      echo -n "  Установить Zapret (DPI bypass)? (Y/n): "
      read -r ans_zapret
      [[ "${ans_zapret,,}" != "n" ]] && install_zapret="1" || install_zapret="0"
      ;;
  esac

  # 4. Сохранить профиль установки
  local profile_json="/var/lib/olcrtc/install-profile.json"
  mkdir -p "$(dirname "$profile_json")" 2>/dev/null || true

  cat > "$profile_json" <<EOF
{
  "installed_at": "$(date -Iseconds 2>/dev/null || date)",
  "access_mode": "$([[ "$access_mode" == "2" ]] && echo "ssh" || echo "http")",
  "components": {
    "tor": $([[ "$install_tor" == "1" ]] && echo "true" || echo "false"),
    "bridges": $([[ "$install_bridges" == "1" ]] && echo "true" || echo "false"),
    "split": $([[ "$install_split" == "1" ]] && echo "true" || echo "false"),
    "zapret": $([[ "$install_zapret" == "1" ]] && echo "true" || echo "false")
  }
}
EOF

  # 5. Экспортировать флаги для install.sh
  [[ "$access_mode" == "2" ]] && export OLC_INSTALL_SSH=1
  [[ "$install_tor" == "0" ]] && export OLC_NO_TOR=1
  [[ "$install_split" == "0" ]] && export OLC_NO_SPLIT=1
  [[ "$install_zapret" == "0" ]] && export OLC_NO_ZAPRET=1
  [[ "$install_bridges" == "0" ]] && export OLC_NO_BRIDGES=1

  # 6. Показать итоговый выбор
  echo ""
  echo "✓ Конфигурация сохранена:"
  echo "  Режим доступа: $([[ "$access_mode" == "2" ]] && echo "SSH-туннель" || echo "HTTP (IP:8888)")"
  echo "  Компоненты:"
  [[ "$install_tor" == "1" ]] && echo "    ✓ Tor" || echo "    ✗ Tor"
  [[ "$install_bridges" == "1" ]] && echo "    ✓ Мосты Tor" || echo "    ✗ Мосты Tor"
  [[ "$install_split" == "1" ]] && echo "    ✓ Split-routing" || echo "    ✗ Split-routing"
  [[ "$install_zapret" == "1" ]] && echo "    ✓ Zapret" || echo "    ✗ Zapret"
  echo ""
  echo "Профиль сохранён в: $profile_json"
  echo ""

  return 0
}

# === Логирование с префиксом ===
olc_log() {
  echo "[olc-core] $*"
}

olc_log_debug() {
  [[ "${OLC_VERBOSE_INSTALL:-0}" == "1" ]] && echo "[olc-core] DEBUG: $*" >&2
}

# === Инициализация (вызывается при source) ===
olc_core_init() {
  validate_flags || return 1
  export_flags
  olc_log_debug "lib-olc-core.sh загружен (режим: $(get_manager_install_mode))"
  return 0
}

# Автоинициализация при source (с безопасным возвратом)
olc_core_init || {
  echo "[olc-core] ОШИБКА: конфликтующие флаги (--manager-stable и --manager-latest одновременно)" >&2
  return 1 2>/dev/null || exit 1
}
