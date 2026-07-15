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

# Progress bar helper — safe wrapper
_olc_show_progress() {
  echo "[PROGRESS-DEBUG] ENTRY" >&2
  [[ "$OLCRTC_TOTAL_STEPS" -le 0 ]] && return 0
  echo "[PROGRESS-DEBUG] after check" >&2
  local curr="$1" total="$2"
  local percent=$(( curr * 100 / total ))
  local width=30
  local filled=$(( width * curr / total ))
  local empty=$(( width - filled ))

  echo "[PROGRESS-DEBUG] building bar" >&2
  local bar=""
  local i
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  echo "[PROGRESS-DEBUG] before printf" >&2
  printf "\r[%s] %d%% (шаг %d/%d)" "$bar" "$percent" "$curr" "$total"
  echo "[PROGRESS-DEBUG] after printf" >&2
  [[ "$curr" -eq "$total" ]] && printf "\n"
  echo "[PROGRESS-DEBUG] EXIT" >&2
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
  echo "[STATE-DEBUG] state_step ENTRY: name=$1" >&2
  local name="$1"; shift
  echo "[STATE-DEBUG] after shift, args=$*" >&2

  _OLCRTC_STEP_NUM=$(( _OLCRTC_STEP_NUM + 1 ))
  echo "[STATE-DEBUG] step num=$_OLCRTC_STEP_NUM" >&2

  echo "[STATE-DEBUG] checking state_already_done" >&2
  if state_already_done "$name"; then
    echo "[STATE-DEBUG] step already done, skipping" >&2
    _state_log "skip $name (already done — resume)"
    return 0
  fi
  echo "[STATE-DEBUG] step not done, continuing" >&2

  # Show progress bar if OLCRTC_TOTAL_STEPS is set
  echo "[STATE-DEBUG] before _olc_show_progress" >&2
  _olc_show_progress "$_OLCRTC_STEP_NUM" "$OLCRTC_TOTAL_STEPS"
  echo "[STATE-DEBUG] after _olc_show_progress" >&2

  # DEBUG: явный вывод в stderr
  echo "[STATE-DEBUG] before _state_log for: $name" >&2
  _state_log "→ $name"
  echo "[STATE-DEBUG] after _state_log" >&2

  local started; started=$(date +%s)
  local rc=0

  echo "[STATE-DEBUG] calling function: $*" >&2
  "$@" || rc=$?
  echo "[STATE-DEBUG] function returned rc=$rc" >&2

  local dur=$(( $(date +%s) - started ))
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
