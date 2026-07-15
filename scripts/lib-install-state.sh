#!/usr/bin/env bash
# Resumable install state machine.
# Stores last-finished step so `--resume` can continue after partial failure
# (e.g. webtunnel build hung, zapret download timeout, network drop mid-install).
#
# Usage:
#   source lib-install-state.sh
#   state_init [--fresh]
#   state_step packages   apt_install_packages   # function name
#   state_step go-toolchain  install_go_toolchain
#   ...
#   state_finish
#
# State file: /var/lib/olcrtc/install-state.json
#   {"started": "...", "last_ok": "step-name", "history": ["step1","step2"], "failed": null}
#
# shellcheck shell=bash

: "${OLCRTC_STATE_DIR:=/var/lib/olcrtc}"
: "${OLCRTC_STATE_FILE:=${OLCRTC_STATE_DIR}/install-state.json}"

# Default behaviour: re-run already-completed steps unless OLCRTC_RESUME=1.
: "${OLCRTC_RESUME:=0}"
# Drop state and start over.
: "${OLCRTC_FRESH:=0}"
# Force re-run specific step even on resume.
: "${OLCRTC_FORCE_STEP:=}"

# Step progress counter (set OLCRTC_TOTAL_STEPS before first state_step for progress bar)
: "${OLCRTC_TOTAL_STEPS:=0}"
_OLCRTC_STEP_NUM=0

# Progress bar — динамический с анимацией
_OLCRTC_PROGRESS_PID=""
_OLCRTC_PROGRESS_CURR=0
_OLCRTC_PROGRESS_TOTAL=0
_OLCRTC_PROGRESS_STEP_NAME=""
_OLCRTC_PROGRESS_SUBSTEP_FILE="/tmp/olc-substep-$$"
_OLCRTC_PROGRESS_SIMPLE_FLAG="/tmp/olc-progress-simple-$$"
_OLCRTC_PROGRESS_ACTIVE=0
_OLCRTC_PROGRESS_SIMPLE=0  # Статичный режим для не-TTY

# Функция для отчёта о подзадаче (вызывается из agent-bootstrap.sh и др.)
_olc_substep() {
  local substep_name="$1"

  # Записать в файл для чтения анимацией
  if [[ -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" ]]; then
    local curr total
    read curr total < "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null || { curr=0; total=0; }
    curr=$(( curr + 1 ))
    echo "$curr $total $substep_name" > "$_OLCRTC_PROGRESS_SUBSTEP_FILE"

    # Если simple mode — сразу печатать статичный прогресс
    # Проверка через файл-флаг вместо переменной окружения
    if [[ -f "$_OLCRTC_PROGRESS_SIMPLE_FLAG" && "$total" -gt 0 ]]; then
      local percent=$(( curr * 100 / total ))
      printf "  → %s (%d/%d, %d%%)\n" "$substep_name" "$curr" "$total" "$percent"
    fi
  fi
}

# Сбросить счётчик подзадач (вызывается в начале state_step)
_olc_substep_reset() {
  local total="${1:-0}"
  echo "0 $total" > "$_OLCRTC_PROGRESS_SUBSTEP_FILE"
}

_olc_show_progress() {
  [[ "$OLCRTC_TOTAL_STEPS" -le 0 ]] && return 0
  local curr="$1" total="$2"
  _OLCRTC_PROGRESS_CURR="$curr"
  _OLCRTC_PROGRESS_TOTAL="$total"
  local percent=$(( curr * 100 / total ))
  local width=30
  local filled=$(( width * curr / total ))
  local empty=$(( width - filled ))

  local bar=""
  local i
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  printf "\r[%s] %d%% (шаг %d/%d)" "$bar" "$percent" "$curr" "$total"
  [[ "$curr" -eq "$total" ]] && printf "\n"
}

# Запуск анимированного прогресс-бара (вызывается в начале state_step)
_olc_progress_start() {
  local step_name="$1"
  _OLCRTC_PROGRESS_STEP_NAME="$step_name"

  # Сбросить simple mode от предыдущего шага
  _OLCRTC_PROGRESS_SIMPLE=0
  rm -f "$_OLCRTC_PROGRESS_SIMPLE_FLAG" 2>/dev/null

  # Если не TTY или OLC_NO_SPINNER=1 → включить simple mode (статичный вывод)
  if [[ ! -t 1 ]] || [[ "${OLC_NO_SPINNER:-0}" == "1" ]]; then
    _OLCRTC_PROGRESS_SIMPLE=1
    _OLCRTC_PROGRESS_ACTIVE=1
    export _OLCRTC_PROGRESS_SIMPLE
    export _OLCRTC_PROGRESS_ACTIVE
    # Создать файл для обмена данными с подзадачами
    echo "0 0" > "$_OLCRTC_PROGRESS_SUBSTEP_FILE"
    # Создать файл-флаг simple mode (для видимости в подпроцессах)
    touch "$_OLCRTC_PROGRESS_SIMPLE_FLAG"
    # Печатать статичный заголовок шага
    if [[ "$OLCRTC_TOTAL_STEPS" -gt 0 ]]; then
      printf "[%d/%d] %s\n" "$_OLCRTC_STEP_NUM" "$OLCRTC_TOTAL_STEPS" "$step_name"
    else
      printf "[шаг] %s\n" "$step_name"
    fi
    return 0
  fi

  # Остановить предыдущую анимацию если была
  _olc_progress_stop >/dev/null 2>&1

  # Создать файл для обмена данными с подзадачами
  echo "0 0" > "$_OLCRTC_PROGRESS_SUBSTEP_FILE"

  # Установить флаг что прогресс-бар активен
  _OLCRTC_PROGRESS_ACTIVE=1
  export _OLCRTC_PROGRESS_ACTIVE

  # Запустить фоновый процесс анимации
  (
    # Игнорировать SIGTERM чтобы не ломать exit code родителя
    trap '' TERM
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    while true; do
      local curr="$_OLCRTC_PROGRESS_CURR"
      local total="$_OLCRTC_PROGRESS_TOTAL"
      [[ "$total" -le 0 ]] && total=1

      # Вычислить общий процент (по шагам)
      local overall_percent=$(( curr * 100 / total ))

      # Прочитать данные о подзадачах из файла
      local substep_curr=0 substep_total=0 substep_name=""
      if [[ -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" ]]; then
        read substep_curr substep_total substep_name < "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null || true
      fi

      # Вычислить процент внутри шага (по подзадачам)
      local substep_percent=0
      if [[ "$substep_total" -gt 0 ]]; then
        substep_percent=$(( substep_curr * 100 / substep_total ))
      fi

      # Использовать процент подзадач если доступен, иначе общий
      local display_percent="$overall_percent"
      [[ "$substep_total" -gt 0 ]] && display_percent="$substep_percent"

      local width=30
      local filled=$(( width * display_percent / 100 ))
      local empty=$(( width - filled ))

      # Построить прогресс-бар
      local bar=""
      local j
      for ((j=0; j<filled; j++)); do bar+="█"; done
      for ((j=0; j<empty; j++)); do bar+="░"; done

      # Очистить строку и вывести: спиннер + бар + процент + шаг + название + подзадача
      local substep_display=""
      if [[ -n "$substep_name" ]]; then
        substep_display=" \033[2m→ $substep_name\033[0m"
      fi

      printf "\r\033[K\033[36m%s\033[0m [%s] %d%% \033[2m(шаг %d/%d)\033[0m %s%s" \
        "${frames[$i]}" "$bar" "$display_percent" "$curr" "$total" "$_OLCRTC_PROGRESS_STEP_NAME" "$substep_display"

      i=$(( (i + 1) % ${#frames[@]} ))
      sleep 0.1
    done
  ) &
  _OLCRTC_PROGRESS_PID=$!
}

# Остановка анимации (вызывается после завершения state_step)
_olc_progress_stop() {
  # Simple mode — только очистка
  if [[ "$_OLCRTC_PROGRESS_SIMPLE" == "1" ]]; then
    _OLCRTC_PROGRESS_ACTIVE=0
    # НЕ сбрасываем _OLCRTC_PROGRESS_SIMPLE здесь — нужен для вывода результата в _state_log
    # НЕ удаляем файл-флаг — нужен для olc_state_line()
    rm -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null
    return 0
  fi

  [[ -z "$_OLCRTC_PROGRESS_PID" ]] && return 0
  kill "$_OLCRTC_PROGRESS_PID" 2>/dev/null && wait "$_OLCRTC_PROGRESS_PID" 2>/dev/null
  _OLCRTC_PROGRESS_PID=""
  # Сбросить флаг активности
  _OLCRTC_PROGRESS_ACTIVE=0
  # Очистить строку с анимацией
  [[ -t 1 ]] && printf "\r\033[K"
  # Удалить файл обмена данными
  rm -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null
}

if [[ -f "${BASH_SOURCE[0]%/*}/lib-olc-ru.sh" ]]; then
  # shellcheck source=lib-olc-ru.sh
  source "${BASH_SOURCE[0]%/*}/lib-olc-ru.sh"
fi
_state_log() {
  if declare -f olc_state_line >/dev/null 2>&1; then
    olc_state_line "$*"
  else
    echo "[state] $*"
  fi
}

state_init() {
  mkdir -p "$OLCRTC_STATE_DIR"
  if [[ "${1:-}" == "--fresh" || "$OLCRTC_FRESH" == "1" ]]; then
    rm -f "$OLCRTC_STATE_FILE"
  fi
  if [[ ! -f "$OLCRTC_STATE_FILE" ]]; then
    printf '{"started":"%s","last_ok":null,"history":[],"failed":null}\n' \
      "$(date -u +%FT%TZ)" > "$OLCRTC_STATE_FILE"
  fi
  # Установить trap для очистки анимации при прерывании
  trap '_olc_progress_stop 2>/dev/null || true' EXIT INT TERM
}

state_already_done() {
  local step="$1"
  # Только в режиме --resume проверяем историю
  [[ "$OLCRTC_RESUME" == "1" ]] || return 1
  [[ "$OLCRTC_FORCE_STEP" == "$step" ]] && return 1

  # Проверяем присутствие в истории
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg s "$step" '.history | index($s) != null' "$OLCRTC_STATE_FILE" >/dev/null 2>&1
    return $?
  else
    grep -q "\"$step\"" "$OLCRTC_STATE_FILE" 2>/dev/null
    return $?
  fi
}

_state_record_ok() {
  local step="$1"
  if command -v jq >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    jq --arg s "$step" --arg t "$(date -u +%FT%TZ)" \
      '.last_ok=$s | .updated=$t | .failed=null | (.history += [$s] | .history |= unique)' \
      "$OLCRTC_STATE_FILE" > "$tmp" && mv "$tmp" "$OLCRTC_STATE_FILE"
  else
    printf '{"last_ok":"%s","updated":"%s"}\n' "$step" "$(date -u +%FT%TZ)" \
      >> "$OLCRTC_STATE_FILE"
  fi
}

_state_record_fail() {
  local step="$1" code="${2:-1}"
  if command -v jq >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    jq --arg s "$step" --arg c "$code" --arg t "$(date -u +%FT%TZ)" \
      '.failed={"step":$s,"code":($c|tonumber),"time":$t}' \
      "$OLCRTC_STATE_FILE" > "$tmp" && mv "$tmp" "$OLCRTC_STATE_FILE"
  fi
}

# state_step <name> <function-or-cmd...>
# If function returns non-zero AND step is critical, abort with helpful message.
# If OLCRTC_SOFT_STEPS includes the step, failure is logged but continues.
state_step() {
  local name="$1"; shift
  _OLCRTC_STEP_NUM=$(( _OLCRTC_STEP_NUM + 1 ))
  if state_already_done "$name"; then
    _state_log "skip $name (already done — resume)"
    return 0
  fi

  # Обновить счётчик для анимации
  _OLCRTC_PROGRESS_CURR="$_OLCRTC_STEP_NUM"
  _OLCRTC_PROGRESS_TOTAL="$OLCRTC_TOTAL_STEPS"

  # Сбросить счётчик подзадач (будет обновляться через _olc_substep)
  _olc_substep_reset 0

  # Экспортировать переменные и функции для использования в подпроцессах
  export _OLCRTC_PROGRESS_SUBSTEP_FILE
  export -f _olc_substep 2>/dev/null || true
  export -f _olc_substep_reset 2>/dev/null || true

  # Запустить анимированный прогресс-бар
  _olc_progress_start "$name"

  local started; started=$(date +%s)
  local rc=0
  "$@" || rc=$?
  local dur=$(( $(date +%s) - started ))

  # Остановить анимацию и очистить строку
  _olc_progress_stop

  if [[ $rc -eq 0 ]]; then
    _state_log "✓ $name (${dur}s)"
    _state_record_ok "$name"
    return 0
  fi
  _state_log "✗ $name (rc=$rc, ${dur}s)"
  _state_record_fail "$name" "$rc"
  case ",${OLCRTC_SOFT_STEPS:-}," in
    *",$name,"*)
      _state_log "step '$name' is soft — continuing"
      return 0
      ;;
  esac
  _state_log "ABORT. Resume with: OLCRTC_RESUME=1 $0 ${OLCRTC_RESUME_HINT:-}"
  return $rc
}

state_finish() {
  if command -v jq >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    jq --arg t "$(date -u +%FT%TZ)" '.finished=$t | .failed=null' \
      "$OLCRTC_STATE_FILE" > "$tmp" && mv "$tmp" "$OLCRTC_STATE_FILE"
  fi
  _state_log "install state OK. State: $OLCRTC_STATE_FILE"
}

state_show() {
  if [[ ! -f "$OLCRTC_STATE_FILE" ]]; then
    echo "no install state"
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    jq . "$OLCRTC_STATE_FILE"
  else
    cat "$OLCRTC_STATE_FILE"
  fi
}
