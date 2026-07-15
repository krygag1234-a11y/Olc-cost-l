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
_OLCRTC_PROGRESS_SUBSTEP_CURR=0
_OLCRTC_PROGRESS_SUBSTEP_TOTAL=0
_OLCRTC_PROGRESS_SUBSTEP_NAME=""
_OLCRTC_PROGRESS_PIPE=""

# Функция для отчёта о подзадаче (вызывается из agent-bootstrap.sh и др.)
_olc_substep() {
  local substep_name="$1"
  _OLCRTC_PROGRESS_SUBSTEP_CURR=$(( _OLCRTC_PROGRESS_SUBSTEP_CURR + 1 ))
  _OLCRTC_PROGRESS_SUBSTEP_NAME="$substep_name"

  # Записать в pipe для анимации
  [[ -n "$_OLCRTC_PROGRESS_PIPE" ]] && echo "$substep_name" > "$_OLCRTC_PROGRESS_PIPE" 2>/dev/null || true
}

# Сбросить счётчик подзадач (вызывается в начале state_step)
_olc_substep_reset() {
  _OLCRTC_PROGRESS_SUBSTEP_CURR=0
  _OLCRTC_PROGRESS_SUBSTEP_TOTAL="${1:-0}"
  _OLCRTC_PROGRESS_SUBSTEP_NAME=""
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

  # Пропустить если не TTY или OLC_NO_SPINNER=1
  [[ ! -t 1 ]] && return 0
  [[ "${OLC_NO_SPINNER:-0}" == "1" ]] && return 0

  # Остановить предыдущую анимацию если была
  _olc_progress_stop >/dev/null 2>&1

  # Создать named pipe для получения уведомлений о подзадачах
  _OLCRTC_PROGRESS_PIPE="/tmp/olc-progress-$$"
  mkfifo "$_OLCRTC_PROGRESS_PIPE" 2>/dev/null || _OLCRTC_PROGRESS_PIPE=""

  # Запустить фоновый процесс анимации
  (
    # Игнорировать SIGTERM чтобы не ломать exit code родителя
    trap '' TERM
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local last_substep=""

    while true; do
      local curr="$_OLCRTC_PROGRESS_CURR"
      local total="$_OLCRTC_PROGRESS_TOTAL"
      [[ "$total" -le 0 ]] && total=1

      # Вычислить общий процент (по шагам)
      local overall_percent=$(( curr * 100 / total ))

      # Вычислить процент внутри шага (по подзадачам)
      local substep_curr="$_OLCRTC_PROGRESS_SUBSTEP_CURR"
      local substep_total="$_OLCRTC_PROGRESS_SUBSTEP_TOTAL"
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

      # Очистить строку и вывести: спиннер + бар + процент + шаг + название
      printf "\r\033[K\033[36m%s\033[0m [%s] %d%% \033[2m(шаг %d/%d)\033[0m %s" \
        "${frames[$i]}" "$bar" "$display_percent" "$curr" "$total" "$_OLCRTC_PROGRESS_STEP_NAME"

      # Вывести текущую подзадачу ниже прогресс-бара если есть
      if [[ -n "$_OLCRTC_PROGRESS_SUBSTEP_NAME" ]] && [[ "$_OLCRTC_PROGRESS_SUBSTEP_NAME" != "$last_substep" ]]; then
        printf "\n\033[2m→ %s\033[0m" "$_OLCRTC_PROGRESS_SUBSTEP_NAME"
        last_substep="$_OLCRTC_PROGRESS_SUBSTEP_NAME"
      fi

      i=$(( (i + 1) % ${#frames[@]} ))
      sleep 0.1
    done
  ) &
  _OLCRTC_PROGRESS_PID=$!
}

# Остановка анимации (вызывается после завершения state_step)
_olc_progress_stop() {
  [[ -z "$_OLCRTC_PROGRESS_PID" ]] && return 0
  kill "$_OLCRTC_PROGRESS_PID" 2>/dev/null && wait "$_OLCRTC_PROGRESS_PID" 2>/dev/null
  _OLCRTC_PROGRESS_PID=""
  # Очистить строку с анимацией
  [[ -t 1 ]] && printf "\r\033[K"
  # Удалить named pipe
  [[ -n "$_OLCRTC_PROGRESS_PIPE" ]] && rm -f "$_OLCRTC_PROGRESS_PIPE" 2>/dev/null
  _OLCRTC_PROGRESS_PIPE=""
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

  # Экспортировать функцию _olc_substep для использования в подпроцессах
  export -f _olc_substep 2>/dev/null || true

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
