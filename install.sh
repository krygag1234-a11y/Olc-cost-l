#!/usr/bin/env bash
# Install or update Olc-cost-l (auto-detect, resumable).
#
# One URL for everything:
#   curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
#   curl -fsSL ... | sudo bash -s -- --no-tor          # foreign VPS
#   curl -fsSL ... | sudo bash -s -- --with-warp       # foreign VPS + Cloudflare WARP (без Tor)
#   curl -fsSL ... | sudo bash -s -- --full            # force clean deps + rebuild
#   curl -fsSL ... | sudo bash -s -- --update          # force update only
#   curl -fsSL ... | sudo bash -s -- --resume          # продолжить с последнего успешного шага
#   curl -fsSL ... | sudo bash -s -- --state           # показать состояние
#   curl -fsSL ... | sudo bash -s -- --no-zapret       # пропустить zapret (для тестов)
#   curl -fsSL ... | sudo bash -s -- --force-sha-update # автообновление SHA256SUMS при несовпадении
#   curl -fsSL ... | sudo bash -s -- --manager-stable  # использовать стабильный fork панели
#   curl -fsSL ... | sudo bash -s -- --manager-latest  # использовать последнюю версию upstream (без pin)
set -euo pipefail

INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"
REPO_URL="${OLC_REPO_URL:-https://github.com/krygag1234-a11y/Olc-cost-l.git}"
BRANCH="${OLC_REPO_BRANCH:-main}"

# Early fatal (before TUI loaded)
fatal_early() {
  echo "" >&2
  echo "[ОШИБКА] $1" >&2
  [[ -n "${2:-}" ]] && echo "Контекст: $2" >&2
  [[ -n "${3:-}" ]] && echo "Подсказка: $3" >&2
  echo "" >&2
  exit 1
}

[[ "$(id -u)" -eq 0 ]] || fatal_early "Требуются права root" "install.sh должен запускаться с sudo" "Используйте: curl ... | sudo bash"

# Load TUI early if available
if [[ -f "$INSTALL_DIR/scripts/lib-tui.sh" ]]; then
  source "$INSTALL_DIR/scripts/lib-tui.sh"
  TUI_AVAILABLE=1
  tui_clear
  tui_banner "Olc-cost-l Installer"
  tui_log_info "Установка/обновление комплекса обхода блокировок для RU VPS"
  tui_divider
else
  TUI_AVAILABLE=0
fi

olc_has_tty() {
  [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; } 2>/dev/null
}

olc_cleanup_disk_junk() {
  rm -f /var/backups/olc-vps/*.tar.gz 2>/dev/null || true
  rm -f /var/backups/olc-vps/*.tsv /var/backups/olc-vps/*.txt 2>/dev/null || true
  rm -rf /root/.cache/go-build /root/.npm/_cacache 2>/dev/null || true
  apt-get clean 2>/dev/null || true
  find /var/log -type f -name '*.gz' -delete 2>/dev/null || true
  journalctl --vacuum-time=1d 2>/dev/null || true
}

# Быстрая проверка до git clone (curl | bash — репо ещё может не быть на диске)
if command -v df >/dev/null 2>&1; then
  _avail="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4+0}')"
  _use="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}')"
  if [[ -n "$_avail" && ( "$_avail" -lt 400 || "$_use" -ge 98 ) ]]; then
    echo "" >&2
    echo "[install] ВНИМАНИЕ: на диске / почти нет места (~${_avail} МБ свободно, занято ${_use}%)." >&2
    echo "[install] Скрипт не сможет клонировать репозиторий или собрать панель." >&2
    
    if olc_has_tty; then
      echo "" >&2
      echo "Хотите очистить временные файлы (кэш Go, npm, apt, логи, бэкапы) прямо сейчас автоматически?" >&2
      echo "1 - Да, очистить мусор (и все локальные бэкапы)" >&2
      echo "2 - Нет, я сам решу эту проблему (установка будет прервана)" >&2
      
      _ans=""
      read -r -p "Введите 1 или 2: " _ans </dev/tty || _ans=""
      if [[ "${_ans,,}" == "1" || "${_ans,,}" == "да" || "${_ans,,}" == "-да" || "${_ans,,}" == "- да" || "${_ans,,}" == "y" || "${_ans,,}" == "yes" ]]; then
        echo "[install] Очистка..." >&2
        olc_cleanup_disk_junk
        
        _avail="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4+0}')"
        _use="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}')"
        if [[ -n "$_avail" && ( "$_avail" -lt 400 || "$_use" -ge 98 ) ]]; then
          [[ ${TUI_AVAILABLE:-0} -eq 1 ]] && tui_fatal "Недостаточно места на диске после очистки" "Свободно: ~${_avail} МБ, занято ${_use}%" "Удалите старые бэкапы/логи вручную или увеличьте диск" || \
            fatal_early "Недостаточно места на диске после очистки (~${_avail} МБ)" "Занято ${_use}%" "Удалите старые файлы или увеличьте диск"
        else
          echo "[install] Очистка помогла. Продолжаем установку (~${_avail} МБ свободно)." >&2
        fi
      else
        echo "[install] Прерывание." >&2
        exit 1
      fi
    else
      echo "[install] Нет интерактивного терминала; пробую автоматическую очистку временных файлов." >&2
      olc_cleanup_disk_junk
      _avail="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4+0}')"
      _use="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}')"
      if [[ -n "$_avail" && ( "$_avail" -lt 400 || "$_use" -ge 98 ) ]]; then
        [[ ${TUI_AVAILABLE:-0} -eq 1 ]] && tui_fatal "Недостаточно места на диске после автоочистки" "Свободно: ~${_avail} МБ, занято ${_use}%" "Освободите диск вручную: rm -rf /root/.cache /var/log/*.gz" || \
          fatal_early "Недостаточно места после автоочистки (~${_avail} МБ, ${_use}% занято)" "" "Освободите диск и повторите"
      fi
      echo "[install] Очистка помогла. Продолжаем установку (~${_avail} МБ свободно)." >&2
    fi
  fi
  unset _avail _use _ans
fi

# curl | bash: BASH_SOURCE[0] is unset under set -u
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR=""
fi
# shellcheck source=scripts/safety-lib.sh
if [[ -f "$SCRIPT_DIR/scripts/safety-lib.sh" ]]; then
  source "$SCRIPT_DIR/scripts/safety-lib.sh"
else
  # curl | bash: safety-lib not on disk yet — minimal guard
  safety_check_install_dir() {
    case "$1" in
      /|/etc|/etc/*|/usr|/usr/*) echo "REFUSE OLC_INSTALL_DIR=$1" >&2; return 1 ;;
    esac
  }
fi
# shellcheck source=scripts/lib-tui.sh
if [[ -f "$SCRIPT_DIR/scripts/lib-tui.sh" ]]; then
  source "$SCRIPT_DIR/scripts/lib-tui.sh"
elif [[ "${TUI_AVAILABLE:-0}" -eq 1 ]]; then
  # curl | bash на установленной системе: настоящий lib-tui.sh уже загружен
  # выше из $INSTALL_DIR — НЕ перезатирать его текстовыми стабами (иначе меню
  # «уже установлен, выберите действие» рисуется примитивным fallback'ом).
  :
else
  # Fallback: define stub functions if TUI not available yet (curl | bash scenario)
  tui_log_step() { echo "→ $*"; }
  tui_log_info() { echo "ℹ $*"; }
  tui_log_success() { echo "✓ $*"; }
  tui_log_warning() { echo "⚠ $*"; }
  tui_log_error() { echo "✗ $*" >&2; }
  tui_divider() { echo "────────────────────────────────────────"; }
  tui_banner() { echo ""; echo "═══ $1 ═══"; echo ""; }
  tui_clear() { :; }
  tui_confirm() {
    local default="${2:-y}"
    [[ "$default" == "n" ]] && return 1
    return 0
  }
  tui_menu() {
    local prompt="$1"; shift
    local i=0
    echo "$prompt" >&2
    for opt in "$@"; do
      echo "$((i+1))) $opt" >&2
      ((i++))
    done
    local choice
    read -p "Выбор (1-$#): " choice >&2 </dev/tty 2>/dev/null || choice=1
    # Return 0-based index
    echo "$(( ${choice:-1} - 1 ))"
  }
fi
# shellcheck source=scripts/lib-swap-auto.sh
if [[ -f "$SCRIPT_DIR/scripts/lib-swap-auto.sh" ]]; then
  source "$SCRIPT_DIR/scripts/lib-swap-auto.sh"
  if olc_swap_check 2>/dev/null; then
    ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
    swap_rec=$(olc_swap_recommend)
    tui_log_warning "Обнаружено мало RAM (${ram_mb}MB) и нет swap. Рекомендуется: ${swap_rec}MB"
    if tui_confirm "Создать swap автоматически?" 2>/dev/null || true; then
      olc_swap_create "$swap_rec" 2>&1 | tee -a /var/log/olc-swap.log
    fi
  fi
fi

safety_check_install_dir "$INSTALL_DIR"

FORCE_MODE=""
BOOT_ARGS=()
SHOW_STATE=0
UNKNOWN_FLAGS=()
PLAN_ONLY=0
CHOOSE_COMPONENTS=0
ACCESS_SET=0        # был ли режим доступа задан флагом (--ssh/--ip и алиасы)
# Запуск БЕЗ флагов = основная интерактивная команда: меню действий (если уже
# установлено) + меню выбора конфигурации (при полной установке).
NO_FLAGS=0
[[ $# -eq 0 ]] && NO_FLAGS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|--update|--fresh) FORCE_MODE="$1" ;;  # MODE передаётся через exec, не через BOOT_ARGS
    --tor|--warp|--zapret|--split|--bridges) BOOT_ARGS+=("$1") ;;
    --no-tor|--no-warp|--no-zapret|--no-split|--no-bridges) BOOT_ARGS+=("$1") ;;
    --foreign|--with-warp|--with-tor|--ru) BOOT_ARGS+=("$1") ;;
    --force-sha-update) export OLCRTC_FORCE_SHA_UPDATE=1; BOOT_ARGS+=("$1") ;;
    --manager-stable) export OLC_MANAGER_STABLE=1; BOOT_ARGS+=("$1") ;;
    --manager-latest) export OLC_MANAGER_LATEST=1; BOOT_ARGS+=("$1") ;;
    --ssh|--localhost|--local-panel|--ip|--public-panel) BOOT_ARGS+=("$1"); ACCESS_SET=1 ;;
    --resume) BOOT_ARGS+=("$1"); export OLCRTC_RESUME=1 ;;
    --state)  SHOW_STATE=1 ;;
    --interactive) CHOOSE_COMPONENTS=1 ;;
    --plan) PLAN_ONLY=1 ;;  # dry-run: напечатать план (mode+args) и выйти, ничего не меняя
    *) UNKNOWN_FLAGS+=("$1") ;;
  esac
  shift
done

# Валидация неизвестных флагов
if [[ "${#UNKNOWN_FLAGS[@]}" -gt 0 ]]; then
  echo "" >&2
  echo "⚠️  ПРЕДУПРЕЖДЕНИЕ: Неизвестные флаги: ${UNKNOWN_FLAGS[*]}" >&2
  echo "" >&2
  echo "Доступные флаги установки:" >&2
  echo "  (без флагов)        Интерактивная установка с меню выбора (рекомендуется)" >&2
  echo "  --full              Полная установка без вопросов (Tor + Split + Zapret + Мосты + Панель)" >&2
  echo "  --update            Только обновление (без переустановки)" >&2
  echo "  --tor / --with-tor  Tor + Панель" >&2
  echo "  --split             Split-routing + Панель (требует --tor)" >&2
  echo "  --zapret            Zapret + Панель" >&2
  echo "  --bridges           Мосты Tor + Панель (требует --tor)" >&2
  echo "  --warp / --with-warp  Cloudflare WARP + Панель (зарубежный VPS, без Tor)" >&2
  echo "  --no-tor / --foreign  Без Tor/Split/мостов (зарубежный VPS)" >&2
  echo "  --no-split / --no-zapret / --no-bridges  Отключить компонент" >&2
  echo "  --manager-stable / --manager-latest  Версия панели (default stable)" >&2
  echo "  --ssh / --ip        Доступ к панели: SSH-туннель или открытый IP" >&2
  echo "  --interactive       Меню выбора компонентов даже вместе с --full" >&2
  echo "  --resume            Продолжить прерванную установку" >&2
  echo "  --state             Показать состояние установки" >&2
  echo "" >&2

  if olc_has_tty && [[ "${TUI_AVAILABLE:-0}" -eq 1 ]] && declare -f tui_menu >/dev/null 2>&1; then
    bad_choice=$(tui_menu "Неизвестные флаги проигнорированы. Что делать?" \
      "Интерактивная установка (меню выбора компонентов)" \
      "Продолжить с настройками по умолчанию" \
      "Отменить установку")
    case "$bad_choice" in
      2) echo "Установка отменена." >&2; exit 1 ;;
      1) ;;  # дефолт (авто-детект режима ниже)
      *) CHOOSE_COMPONENTS=1 ;;
    esac
  elif olc_has_tty; then
    echo -n "Продолжить установку с интерактивным меню? (y/N): " >&2
    read -r answer </dev/tty || answer="n"
    if [[ "${answer,,}" == "y" ]]; then
      CHOOSE_COMPONENTS=1
    else
      echo "Установка отменена." >&2
      exit 1
    fi
  else
    [[ ${TUI_AVAILABLE:-0} -eq 1 ]] && tui_fatal "Нет интерактивного терминала для меню" "Неизвестные флаги требуют выбора через меню" "Используйте правильные флаги: --full, --no-tor, --with-warp, --update" || \
      fatal_early "Нет интерактивного терминала" "Неизвестные флаги требуют меню" "Используйте правильные флаги установки"
  fi
fi

# ── Основная интерактивная команда (без флагов, свежая система) ──────────────
# Запуск без флагов на чистой системе → предложить меню выбора конфигурации.
# С --full и прочими флагами это меню НЕ показывается (TUI-прогресс всё равно
# будет). --interactive форсирует меню даже вместе с флагами.
if [[ "$CHOOSE_COMPONENTS" -eq 1 ]] || { [[ "$NO_FLAGS" -eq 1 ]] && olc_has_tty; }; then
  if [[ -f "$INSTALL_DIR/scripts/lib-olc-core.sh" ]]; then
    # На свежей системе (нет detect) меню выбора компонентов; если уже
    # установлено — этим займётся меню «выберите действие» ниже (auto-detect).
    _pre_detect="fresh"
    [[ -x "$INSTALL_DIR/scripts/olc-detect-install.sh" ]] && \
      _pre_detect="$("$INSTALL_DIR/scripts/olc-detect-install.sh" 2>/dev/null || echo fresh)"
    if [[ "$CHOOSE_COMPONENTS" -eq 1 || "$_pre_detect" == "fresh" ]]; then
      source "$INSTALL_DIR/scripts/lib-olc-core.sh"
      if declare -f interactive_install_menu >/dev/null 2>&1; then
        interactive_install_menu || { echo "Установка отменена." >&2; exit 1; }
        # Перенести выбор меню (OLC_NO_* / OLC_INSTALL_SSH) в BOOT_ARGS
        [[ "${OLC_NO_TOR:-0}" == "1" ]]     && BOOT_ARGS+=(--no-tor)
        [[ "${OLC_NO_SPLIT:-0}" == "1" ]]   && BOOT_ARGS+=(--no-split)
        [[ "${OLC_NO_ZAPRET:-0}" == "1" ]]  && BOOT_ARGS+=(--no-zapret)
        [[ "${OLC_NO_BRIDGES:-0}" == "1" ]] && BOOT_ARGS+=(--no-bridges)
        if [[ "${OLC_INSTALL_SSH:-0}" == "1" ]]; then BOOT_ARGS+=(--ssh); else BOOT_ARGS+=(--ip); fi
        ACCESS_SET=1  # меню компонентов уже спросило режим доступа
        # Меню = осознанный выбор полной конфигурации → форсируем режим full
        [[ -z "$FORCE_MODE" ]] && FORCE_MODE="--full"
      fi
    fi
    unset _pre_detect
  else
    [[ ${TUI_AVAILABLE:-0} -eq 1 ]] && tui_log_warning "lib-olc-core.sh не найден — меню выбора недоступно, ставим полную конфигурацию" || \
      echo "[install] lib-olc-core.sh не найден — меню выбора недоступно" >&2
  fi
fi

if [[ "$SHOW_STATE" -eq 1 ]]; then
  if [[ -f /var/lib/olcrtc/install-state.json ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq . /var/lib/olcrtc/install-state.json
    else
      cat /var/lib/olcrtc/install-state.json
    fi
  else
    echo "[install] состояние установки ещё не сохранено (первый запуск?)"
  fi
  exit 0
fi

resilient_git() {
  local op="$1"; shift
  local attempt rc
  for attempt in 1 2 3; do
    rc=0
    timeout 90 git \
      -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 \
      -c http.postBuffer=524288000 \
      "$@" || rc=$?
    if [[ $rc -eq 0 ]]; then
      return 0
    fi
    echo "[install] git $op: попытка $attempt не удалась (код $rc), повтор…" >&2
    sleep $((attempt * 5))
  done
  echo "[install] git $op: три попытки исчерпаны — проверьте сеть и DNS" >&2
  return 1
}

DETECT="$INSTALL_DIR/scripts/olc-detect-install.sh"
STATE="fresh"
if [[ -x "$DETECT" ]]; then
  STATE="$("$DETECT" 2>/dev/null || echo fresh)"
fi
# Тест-хук: заставить считать систему чистой (для PTY-проверки меню без реальной
# установки). Только для тестов — на боевом не задаётся.
[[ "${OLC_ASSUME_FRESH:-0}" == "1" ]] && STATE="fresh"

if [[ "$FORCE_MODE" == "--full" || "$FORCE_MODE" == "--fresh" ]]; then
  if [[ "$STATE" == "installed" || "$STATE" == "partial" ]]; then
    tui_log_warning "Система уже установлена ($STATE). --full → умное обновление (пересборка + сервисы)."
    tui_log_info "Для полной переустановки с нуля используйте: sudo olc-purge && curl ... | sudo bash"
    MODE=update
  else
    MODE=full
  fi
elif [[ "$FORCE_MODE" == "--update" ]]; then
  MODE=update
else
  if [[ "$STATE" == "installed" || "$STATE" == "partial" ]]; then
    if olc_has_tty; then
      echo "" >&2
      if [[ -d "$INSTALL_DIR/.git" ]]; then
        echo "Проверка актуальности репозитория..." >&2
        local_sha="$(git -C "$INSTALL_DIR" rev-parse HEAD 2>/dev/null || true)"
        remote_sha="$(git ls-remote "$REPO_URL" "$BRANCH" 2>/dev/null | awk '{print $1}' || true)"
        if [[ -n "$local_sha" && "$local_sha" == "$remote_sha" ]]; then
          echo "Репозиторий уже актуален." >&2
          git -C "$INSTALL_DIR" log -1 --format="Текущая версия: %h - %s (%cd)" --date=format:"%Y-%m-%d %H:%M" >&2
        else
          echo "Доступны обновления репозитория!" >&2
        fi
      fi
      
      # Используем TUI меню с 3 опциями
      selected=$(tui_menu "Olc-cost-l уже установлен ($STATE). Выберите действие:" \
        "Доустановка (умное обновление - skip работающих компонентов)" \
        "Обновление (полная пересборка - patches, binaries, lists)" \
        "Переустановить полностью с нуля" \
        "Отмена")
      
      # tui_menu returns 0-based index
      case "$selected" in
        3) echo "Установка отменена." >&2; exit 0 ;;
        2) MODE=full ;;
        1) MODE=update ;;
        0) MODE=incremental ;;
        *) MODE=incremental ;;
      esac
    else
      MODE=update
    fi
  else
    MODE=full
  fi
fi

tui_log_step "Обнаружено: $STATE → режим: $MODE (full=полная, update=обновление)"

# --plan: dry-run — вывести разобранный план и выйти БЕЗ клонирования/сборки.
# Используется scripts/test-install-flags.sh для проверки, что явные флаги не
# ломают парсинг install.sh и корректно транслируются в agent-bootstrap.
if [[ "$PLAN_ONLY" -eq 1 ]]; then
  echo "[install-plan] state=$STATE mode=$MODE boot_args=[${BOOT_ARGS[*]:-}] force_mode=${FORCE_MODE:-none}"
  if [[ -x "$INSTALL_DIR/scripts/agent-bootstrap.sh" ]]; then
    boot_mode="--full"
    [[ "$MODE" == "update" ]] && boot_mode="--update"
    [[ "$MODE" == "incremental" ]] && boot_mode="--incremental"
    OLC_REPO_ROOT="$INSTALL_DIR" bash "$INSTALL_DIR/scripts/agent-bootstrap.sh" "$boot_mode" "${BOOT_ARGS[@]}" --plan
  fi
  exit 0
fi

# ── Добор недостающих измерений выбора ───────────────────────────────────────
# Флаг пропускает ТОЛЬКО тот выбор, который он покрывает. Пример: дан --full
# (набор компонентов), но НЕ указан --ssh/--ip → режим доступа к панели ещё не
# определён, спрашиваем его отдельным меню. Если бы был --ssh/--ip — не спросим.
# Так «поставь без вопросов» = дать флаги на ВСЕ измерения (--full --ip).
# Только на новой установке (MODE=full) и при наличии терминала.
if [[ "$MODE" == "full" && "$ACCESS_SET" -eq 0 ]] && olc_has_tty \
   && [[ "${TUI_AVAILABLE:-0}" -eq 1 ]] && declare -f tui_menu >/dev/null 2>&1; then
  _acc=$(tui_menu "Режим доступа к панели (флаг --ssh/--ip не задан):" \
    "HTTP — панель доступна по IP:8888 (проще)" \
    "SSH — панель только через SSH-туннель (безопаснее)")
  case "$_acc" in
    1) BOOT_ARGS+=(--ssh) ;;
    *) BOOT_ARGS+=(--ip) ;;
  esac
  ACCESS_SET=1
  unset _acc
fi

# Тест-хук: остановиться сразу после добора выбора и напечатать итоговые
# аргументы (PTY-проверка меню доступа без реальной установки). Только тесты.
if [[ "${OLC_EXIT_AFTER_PROMPT:-0}" == "1" ]]; then
  echo "[install-postprompt] mode=$MODE access_set=$ACCESS_SET boot_args=[${BOOT_ARGS[*]:-}]"
  exit 0
fi

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  [[ ${TUI_AVAILABLE:-0} -eq 1 ]] && tui_log_step "Клонирование репозитория..."
  tui_log_step "Клонирование $REPO_URL → $INSTALL_DIR"
  rm -rf "$INSTALL_DIR.partial"
  resilient_git clone clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR.partial" || {
    [[ ${TUI_AVAILABLE:-0} -eq 1 ]] && tui_fatal "Не удалось клонировать репозиторий" "URL: $REPO_URL, ветка: $BRANCH" "Проверьте сеть/DNS: ping github.com && curl -I https://github.com" || \
      fatal_early "Не удалось клонировать репозиторий" "Сеть/DNS недоступны" "Проверьте подключение и повторите"
    rm -rf "$INSTALL_DIR.partial"
  }
  [[ ${TUI_AVAILABLE:-0} -eq 1 ]] && tui_log_success "Репозиторий склонирован успешно"
  mv "$INSTALL_DIR.partial" "$INSTALL_DIR"
else
  tui_log_step "Git fetch+обновление $INSTALL_DIR (с повторами при обрыве)"
  if ! resilient_git fetch -C "$INSTALL_DIR" fetch --depth 50 origin "$BRANCH"; then
    echo "[install] внимание: fetch не удался — продолжаем с локальной копией на VPS" >&2
  fi
  if git -C "$INSTALL_DIR" diff --quiet 2>/dev/null && git -C "$INSTALL_DIR" diff --cached --quiet 2>/dev/null; then
    git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH" 2>/dev/null \
      || git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH" 2>/dev/null \
      || true
  else
    tui_log_warning "На VPS были локальные правки — сброс к origin/$BRANCH"
    git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH" 2>/dev/null || \
      git -C "$INSTALL_DIR" reset --hard "$BRANCH" 2>/dev/null || true
  fi
fi

export OLC_REPO_ROOT="$INSTALL_DIR"
# shellcheck source=scripts/lib-disk-preflight.sh
source "$INSTALL_DIR/scripts/lib-disk-preflight.sh"
olc_preflight_disk_space "install (перед bootstrap)" || exit 1
# shellcheck source=scripts/lib-vps-backup.sh
source "$INSTALL_DIR/scripts/lib-vps-backup.sh"
olc_preflight_vps_backup "install" || true
# shellcheck source=scripts/lib-git-safe.sh
source "$INSTALL_DIR/scripts/lib-git-safe.sh"
olc_git_safe_register "$INSTALL_DIR"
# shellcheck source=scripts/lib-olc-core.sh
source "$INSTALL_DIR/scripts/lib-olc-core.sh"
ln -sfn "$INSTALL_DIR" /opt/olcrtc 2>/dev/null || true
chmod +x "$INSTALL_DIR"/scripts/*.sh "$INSTALL_DIR"/install.sh 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-update.sh" /usr/local/bin/olc-update 2>/dev/null || true
tui_log_info "Доступна короткая команда обновления/доустановки: olc-update" >&2
ln -sfn "$INSTALL_DIR/scripts/olc-feature.sh" /usr/local/bin/olc-feature 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-sync-panel-host.sh" /usr/local/bin/olc-sync-panel-host 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-split-analyze.sh" /usr/local/bin/olc-split-analyze 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-profile.sh" /usr/local/bin/olc-profile 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-vps-backup.sh" /usr/local/bin/olc-vps-backup 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-disk-check.sh" /usr/local/bin/olc-disk-check 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-panel-verify.sh" /usr/local/bin/olc-panel-verify 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-export-golden-panel.sh" /usr/local/bin/olc-export-golden-panel 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-sync-from-vps.sh" /usr/local/bin/olc-sync-from-vps 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-panel-refresh-local.sh" /usr/local/bin/olc-panel-refresh-local 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-vps-snapshot.sh" /usr/local/bin/olc-vps-snapshot 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-cleanup-caches.sh" /usr/local/bin/olc-cleanup-caches 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-purge.sh" /usr/local/bin/olc-purge 2>/dev/null || true

# Передаём режим в agent-bootstrap.sh
if [[ "$MODE" == "full" ]]; then
  exec "$INSTALL_DIR/scripts/agent-bootstrap.sh" --full "${BOOT_ARGS[@]}"
elif [[ "$MODE" == "update" ]]; then
  exec "$INSTALL_DIR/scripts/agent-bootstrap.sh" --update "${BOOT_ARGS[@]}"
elif [[ "$MODE" == "incremental" ]]; then
  exec "$INSTALL_DIR/scripts/agent-bootstrap.sh" --incremental "${BOOT_ARGS[@]}"
else
  exec "$INSTALL_DIR/scripts/agent-bootstrap.sh" --full "${BOOT_ARGS[@]}"
fi
