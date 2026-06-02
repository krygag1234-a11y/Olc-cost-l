#!/usr/bin/env bash
# Централизованная библиотека для общей логики install.sh, olc-update.sh, agent-bootstrap.sh
# Управление флагами, переменными окружения, и общими функциями

# Защита от двойного source
[[ -n "${_LIB_OLC_CORE_LOADED:-}" ]] && return 0
_LIB_OLC_CORE_LOADED=1

# === Глобальные переменные ===
# Флаги устанавливаются через parse_common_flags()
declare -g OLC_MANAGER_STABLE="${OLC_MANAGER_STABLE:-0}"
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
