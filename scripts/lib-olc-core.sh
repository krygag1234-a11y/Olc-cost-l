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

    # Проверка TTY перед read
    if [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; } 2>/dev/null; then
      echo "Продолжить установку с интерактивным меню? (y/N): " >&2
      read -r answer </dev/tty || answer="n"
      if [[ "${answer,,}" == "y" ]]; then
        return 0  # Продолжить с меню
      else
        echo "Установка отменена." >&2
        return 1
      fi
    else
      echo "Нет интерактивного терминала. Используйте правильные флаги." >&2
      return 1
    fi
  elif [[ "$script_mode" == "update" ]]; then
    echo "Доступные флаги обновления:" >&2
    echo "  --manager-latest    Использовать последнюю upstream версию панели" >&2
    echo "  --force-sha-update  Принудительно обновить pinned SHA" >&2
    echo "  --resume            Продолжить прерванное обновление" >&2
    echo "  --fresh-state       Очистить состояние и начать заново" >&2
    echo "" >&2

    # Проверка TTY перед read
    if [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; } 2>/dev/null; then
      echo "Продолжить обновление без этого флага? (Y/n): " >&2
      read -r answer </dev/tty || answer="y"
      if [[ "${answer,,}" != "n" ]]; then
        echo "✓ Продолжаю обновление с дефолтными настройками..." >&2
        return 0
      else
        echo "Обновление отменено." >&2
        return 1
      fi
    else
      echo "Нет интерактивного терминала. Продолжаю с дефолтными настройками." >&2
      return 0
    fi
  fi
}

# === Интерактивное меню установки ===
interactive_install_menu() {
  # Проверка TTY перед запуском меню
  if ! { [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; }; } 2>/dev/null; then
    echo "[olc-core] Нет интерактивного терминала — меню недоступно" >&2
    return 1
  fi

  local access_mode components_mode menu_choice
  echo ""
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║ Интерактивная установка Olc-cost-l                       ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo ""

  # Тот же tui_menu, что использует olc-update: стрелки/цифры/Enter,
  # чтение из /dev/tty и стирание кадра после выбора.
  if [[ "${OLC_INSTALL_ACCESS_PRESET:-}" == "ssh" ]]; then
    access_mode="3"
  elif [[ -n "${OLC_INSTALL_ACCESS_PRESET:-}" || -n "${OLC_INSTALL_TLS_PRESET:-}" ]]; then
    case "${OLC_INSTALL_TLS_PRESET:-selfsigned}" in
      letsencrypt) access_mode="1" ;;
      selfsigned|https) access_mode="2" ;;
      http) access_mode="4" ;;
      *) access_mode="2" ;;
    esac
  else
    if declare -f tui_menu >/dev/null 2>&1; then
      menu_choice="$(tui_menu "Режим доступа к панели:" \
        "IP + HTTPS — доверенный Let's Encrypt, без предупреждения (публичный IP + порт 80)" \
        "IP + HTTPS — self-signed (браузер предупредит)" \
        "SSH + HTTP — панель только через SSH-туннель" \
        "IP + HTTP — без TLS")"
      access_mode="$(( ${menu_choice:-0} + 1 ))"
    else
      echo "1) IP + HTTPS — доверенный Let's Encrypt (публичный IP + порт 80)"
      echo "2) IP + HTTPS — self-signed (браузер предупредит)"
      echo "3) SSH + HTTP — панель только через SSH-туннель"
      echo "4) IP + HTTP — без TLS"
      read -r -p "Ваш выбор (1-4) [2]: " access_mode </dev/tty || access_mode="2"
      access_mode="${access_mode:-2}"
    fi
  fi

  if declare -f tui_menu >/dev/null 2>&1; then
    menu_choice="$(tui_menu "Компоненты для установки:" \
      "Полная установка (Tor + Split + Zapret + Мосты)" \
      "Без Tor (только Zapret для иностранного VPS)" \
      "Без Split (весь трафик через Tor)" \
      "Выборочная установка (выбрать компоненты)")"
    components_mode="$(( ${menu_choice:-0} + 1 ))"
  else
    echo "1) Полная установка (Tor + Split + Zapret + Мосты)"
    echo "2) Без Tor (только Zapret для иностранного VPS)"
    echo "3) Без Split (весь трафик через Tor)"
    echo "4) Выборочная установка (выбрать компоненты)"
    read -r -p "Ваш выбор (1-4) [1]: " components_mode </dev/tty || components_mode="1"
    components_mode="${components_mode:-1}"
  fi

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
      local ans_tor ans_bridges ans_split ans_zapret
      if declare -f tui_menu >/dev/null 2>&1; then
        ans_tor="$(tui_menu "Установить Tor?" "Да" "Нет")"
        [[ "${ans_tor:-0}" == "0" ]] && install_tor="1" || install_tor="0"
      else
        read -r -p "Установить Tor? (Y/n): " ans_tor </dev/tty || ans_tor="y"
        [[ "${ans_tor,,}" != "n" ]] && install_tor="1" || install_tor="0"
      fi

      if [[ "$install_tor" == "1" ]]; then
        if declare -f tui_menu >/dev/null 2>&1; then
          ans_bridges="$(tui_menu "Установить мосты Tor?" "Да" "Нет")"
          [[ "${ans_bridges:-0}" == "0" ]] && install_bridges="1" || install_bridges="0"
          ans_split="$(tui_menu "Установить Split-routing?" "Да" "Нет")"
          [[ "${ans_split:-0}" == "0" ]] && install_split="1" || install_split="0"
        else
          read -r -p "Установить мосты Tor? (Y/n): " ans_bridges </dev/tty || ans_bridges="y"
          [[ "${ans_bridges,,}" != "n" ]] && install_bridges="1" || install_bridges="0"
          read -r -p "Установить Split-routing? (Y/n): " ans_split </dev/tty || ans_split="y"
          [[ "${ans_split,,}" != "n" ]] && install_split="1" || install_split="0"
        fi
      fi

      if declare -f tui_menu >/dev/null 2>&1; then
        ans_zapret="$(tui_menu "Установить Zapret (DPI bypass)?" "Да" "Нет")"
        [[ "${ans_zapret:-0}" == "0" ]] && install_zapret="1" || install_zapret="0"
      else
        read -r -p "Установить Zapret (DPI bypass)? (Y/n): " ans_zapret </dev/tty || ans_zapret="y"
        [[ "${ans_zapret,,}" != "n" ]] && install_zapret="1" || install_zapret="0"
      fi
      ;;
  esac

  # 4. Сохранить профиль установки
  local profile_json="${OLC_INSTALL_PROFILE_PATH:-/var/lib/olcrtc/install-profile.json}"
  mkdir -p "$(dirname "$profile_json")" 2>/dev/null || true

  cat > "$profile_json" <<EOF
{
  "installed_at": "$(date -Iseconds 2>/dev/null || date)",
  "access_mode": "$([[ "$access_mode" == "3" ]] && echo "ssh" || echo "ip")",
  "tls_mode": "$(case "$access_mode" in 1) echo "letsencrypt" ;; 2) echo "selfsigned" ;; *) echo "http" ;; esac)",
  "components": {
    "tor": $([[ "$install_tor" == "1" ]] && echo "true" || echo "false"),
    "bridges": $([[ "$install_bridges" == "1" ]] && echo "true" || echo "false"),
    "split": $([[ "$install_split" == "1" ]] && echo "true" || echo "false"),
    "zapret": $([[ "$install_zapret" == "1" ]] && echo "true" || echo "false")
  }
}
EOF

  # 5. Экспортировать флаги для install.sh
  unset OLC_INSTALL_SSH OLC_INSTALL_ACCESS_MODE OLC_INSTALL_TLS_MODE OLC_NO_TOR OLC_NO_SPLIT OLC_NO_ZAPRET OLC_NO_BRIDGES
  if [[ "$access_mode" == "1" ]]; then
    export OLC_INSTALL_ACCESS_MODE="ip" OLC_INSTALL_TLS_MODE="letsencrypt"
  elif [[ "$access_mode" == "2" ]]; then
    export OLC_INSTALL_ACCESS_MODE="ip" OLC_INSTALL_TLS_MODE="selfsigned"
  elif [[ "$access_mode" == "3" ]]; then
    export OLC_INSTALL_SSH=1 OLC_INSTALL_ACCESS_MODE="ssh" OLC_INSTALL_TLS_MODE="http"
  else
    export OLC_INSTALL_ACCESS_MODE="ip" OLC_INSTALL_TLS_MODE="http"
  fi
  [[ "$install_tor" == "0" ]] && export OLC_NO_TOR=1
  [[ "$install_split" == "0" ]] && export OLC_NO_SPLIT=1
  [[ "$install_zapret" == "0" ]] && export OLC_NO_ZAPRET=1
  [[ "$install_bridges" == "0" ]] && export OLC_NO_BRIDGES=1

  # 6. Показать итоговый выбор
  echo ""
  echo "✓ Конфигурация сохранена:"
  case "$access_mode" in
    1) echo "  Режим доступа: IP + HTTPS (доверенный сертификат Let's Encrypt)" ;;
    2) echo "  Режим доступа: IP + HTTPS (self-signed)" ;;
    3) echo "  Режим доступа: SSH-туннель + HTTP" ;;
    *) echo "  Режим доступа: IP + HTTP" ;;
  esac
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

# === Интерактивное меню обновления ===
interactive_update_menu() {
  # Проверка TTY перед запуском меню
  if ! { [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; }; } 2>/dev/null; then
    echo "[olc-core] Нет интерактивного терминала — меню недоступно" >&2
    return 1
  fi

  echo ""
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║ Интерактивное обновление Olc-cost-l                      ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo ""

  # Загрузить текущий профиль установки
  local profile_json="/var/lib/olcrtc/install-profile.json"
  local current_tor="неизвестно"
  local current_split="неизвестно"
  local current_zapret="неизвестно"
  local current_bridges="неизвестно"
  local current_access="неизвестно"

  if [[ -f "$profile_json" ]]; then
    current_tor=$(jq -r '.components.tor // "unknown"' "$profile_json" 2>/dev/null || echo "unknown")
    current_split=$(jq -r '.components.split // "unknown"' "$profile_json" 2>/dev/null || echo "unknown")
    current_zapret=$(jq -r '.components.zapret // "unknown"' "$profile_json" 2>/dev/null || echo "unknown")
    current_bridges=$(jq -r '.components.bridges // "unknown"' "$profile_json" 2>/dev/null || echo "unknown")
    current_access=$(jq -r '.access_mode // "unknown"' "$profile_json" 2>/dev/null || echo "unknown")
  fi

  echo "📋 Текущая конфигурация:"
  echo "  Режим доступа: $current_access"
  echo "  Компоненты:"
  echo "    Tor: $current_tor"
  echo "    Мосты Tor: $current_bridges"
  echo "    Split-routing: $current_split"
  echo "    Zapret: $current_zapret"
  echo ""

  echo "🔧 Что вы хотите сделать?"
  echo "  [1] Обновить существующие компоненты (рекомендуется)"
  echo "  [2] Доустановить недостающие компоненты"
  echo "  [3] Сменить режим доступа к панели (SSH ↔ IP)"
  echo "  [4] Обновить версию панели (stable → latest или наоборот)"
  echo -n "Ваш выбор (1-4) [1]: "
  read -r update_action </dev/tty || update_action="1"
  update_action="${update_action:-1}"

  case "$update_action" in
    1) # Обновить существующие
      echo ""
      echo "✓ Будут обновлены все установленные компоненты"
      export OLC_UPDATE_MODE="incremental"
      ;;
    2) # Доустановить недостающие
      echo ""
      echo "📦 Выберите компоненты для доустановки:"

      [[ "$current_tor" == "false" ]] && {
        echo -n "  Установить Tor? (y/N): "
        read -r ans_tor </dev/tty || ans_tor="n"
        [[ "${ans_tor,,}" == "y" ]] && export ENABLE_TOR=1
      }

      [[ "$current_bridges" == "false" ]] && {
        echo -n "  Установить мосты Tor? (y/N): "
        read -r ans_bridges </dev/tty || ans_bridges="n"
        [[ "${ans_bridges,,}" == "y" ]] && export ENABLE_BRIDGES=1
      }

      [[ "$current_split" == "false" ]] && {
        echo -n "  Установить Split-routing? (y/N): "
        read -r ans_split </dev/tty || ans_split="n"
        [[ "${ans_split,,}" == "y" ]] && export ENABLE_SPLIT=1
      }

      [[ "$current_zapret" == "false" ]] && {
        echo -n "  Установить Zapret? (y/N): "
        read -r ans_zapret </dev/tty || ans_zapret="n"
        [[ "${ans_zapret,,}" == "y" ]] && export OLCRTC_ENABLE_ZAPRET=1
      }

      export OLC_UPDATE_MODE="incremental"
      ;;
    3) # Сменить режим доступа
      echo ""
      echo "🔒 Выберите новый режим доступа:"
      echo "  [1] IP + HTTPS — доверенный Let's Encrypt (публичный IP + порт 80)"
      echo "  [2] IP + HTTPS — self-signed (браузер предупредит)"
      echo "  [3] SSH + HTTP — панель только через SSH-туннель"
      echo "  [4] IP + HTTP — без TLS"
      echo -n "Ваш выбор (1-4) [2]: "
      read -r new_access </dev/tty || new_access="2"
      case "${new_access:-2}" in
        1) export OLC_INSTALL_SSH=0 PANEL_ACCESS=ip PANEL_TLS=1 PANEL_TLS_MODE=letsencrypt ;;
        2) export OLC_INSTALL_SSH=0 PANEL_ACCESS=ip PANEL_TLS=1 PANEL_TLS_MODE=selfsigned ;;
        3) export OLC_INSTALL_SSH=1 PANEL_ACCESS=ssh PANEL_TLS=0 PANEL_TLS_MODE=http ;;
        4) export OLC_INSTALL_SSH=0 PANEL_ACCESS=ip PANEL_TLS=0 PANEL_TLS_MODE=http ;;
        *) export OLC_INSTALL_SSH=0 PANEL_ACCESS=ip PANEL_TLS=1 PANEL_TLS_MODE=selfsigned ;;
      esac
      profile_set_panel_access "$PANEL_ACCESS"
      profile_set_panel_tls "$PANEL_TLS_MODE"
      ;;
    4) # Сменить версию панели
      echo ""
      echo "📦 Выберите версию панели:"
      echo "  [1] Stable fork (рекомендуется, по умолчанию)"
      echo "  [2] Latest upstream (экспериментальная)"
      echo -n "Ваш выбор (1-2) [1]: "
      read -r panel_version </dev/tty || panel_version="1"

      if [[ "$panel_version" == "2" ]]; then
        export OLC_MANAGER_LATEST=1
        echo "⚠️  ВНИМАНИЕ: Будет установлена экспериментальная версия upstream"
      else
        export OLC_MANAGER_STABLE=1
        echo "✓ Будет установлена стабильная версия (stable fork)"
      fi
      ;;
  esac

  echo ""
  echo "✓ Конфигурация обновления сохранена"
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
