#!/usr/bin/env bash
# Modern output library: colors, icons, progress, structured messages.
[[ -n "${_OLC_OUTPUT_LOADED:-}" ]] && return 0
_OLC_OUTPUT_LOADED=1

# Color codes (ANSI)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
  _C_RESET='\033[0m'
  _C_BOLD='\033[1m'
  _C_DIM='\033[2m'
  _C_RED='\033[31m'
  _C_GREEN='\033[32m'
  _C_YELLOW='\033[33m'
  _C_BLUE='\033[34m'
  _C_MAGENTA='\033[35m'
  _C_CYAN='\033[36m'
  _C_WHITE='\033[37m'
  _C_GRAY='\033[90m'
else
  _C_RESET='' _C_BOLD='' _C_DIM='' _C_RED='' _C_GREEN='' _C_YELLOW=''
  _C_BLUE='' _C_MAGENTA='' _C_CYAN='' _C_WHITE='' _C_GRAY=''
fi

# Icons
_ICON_OK="✓"
_ICON_FAIL="✗"
_ICON_WARN="⚠"
_ICON_INFO="ℹ"
_ICON_ARROW="→"
_ICON_BULLET="•"
_ICON_CLOCK="⏱"
_ICON_ROCKET="🚀"
_ICON_WRENCH="🔧"
_ICON_PACKAGE="📦"
_ICON_NETWORK="🌐"
_ICON_SHIELD="🛡"
_ICON_FIRE="🔥"

# Print functions
olc_print_header() {
  local title="$1"
  echo -e "\n${_C_BOLD}${_C_CYAN}╔═══════════════════════════════════════════════════════════╗${_C_RESET}"
  printf "${_C_BOLD}${_C_CYAN}║${_C_RESET} ${_C_BOLD}%-57s${_C_RESET} ${_C_BOLD}${_C_CYAN}║${_C_RESET}\n" "$title"
  echo -e "${_C_BOLD}${_C_CYAN}╚═══════════════════════════════════════════════════════════╝${_C_RESET}\n"
}

olc_print_section() {
  local title="$1"
  echo -e "\n${_C_BOLD}${_C_BLUE}▶ ${title}${_C_RESET}"
  echo -e "${_C_DIM}${_C_GRAY}────────────────────────────────────────────────────────────${_C_RESET}"
}

olc_print_step() {
  local msg="$1"
  echo -e "${_C_CYAN}${_ICON_ARROW}${_C_RESET} ${msg}"
}

olc_print_ok() {
  local msg="$1"
  echo -e "${_C_GREEN}${_ICON_OK}${_C_RESET} ${_C_GREEN}${msg}${_C_RESET}"
}

olc_print_fail() {
  local msg="$1"
  echo -e "${_C_RED}${_ICON_FAIL}${_C_RESET} ${_C_RED}${msg}${_C_RESET}" >&2
}

olc_print_warn() {
  local msg="$1"
  echo -e "${_C_YELLOW}${_ICON_WARN}${_C_RESET} ${_C_YELLOW}${msg}${_C_RESET}" >&2
}

olc_print_info() {
  local msg="$1"
  echo -e "${_C_BLUE}${_ICON_INFO}${_C_RESET} ${_C_DIM}${msg}${_C_RESET}"
}

olc_print_bullet() {
  local msg="$1"
  echo -e "  ${_C_GRAY}${_ICON_BULLET}${_C_RESET} ${msg}"
}

olc_print_key_value() {
  local key="$1" value="$2"
  printf "  ${_C_CYAN}%-20s${_C_RESET} ${_C_WHITE}%s${_C_RESET}\n" "$key:" "$value"
}

# Progress spinner
_OLC_SPINNER_PID=""
_OLC_SPINNER_MSG=""

olc_spinner_start() {
  local msg="$1"
  _OLC_SPINNER_MSG="$msg"

  if [[ ! -t 1 ]] || [[ "${OLC_NO_SPINNER:-0}" == "1" ]]; then
    echo -e "${_C_CYAN}${_ICON_CLOCK}${_C_RESET} ${msg}..."
    return
  fi

  {
    local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while true; do
      printf "\r${_C_CYAN}%s${_C_RESET} %s..." "${spinner_chars:i++%${#spinner_chars}:1}" "$_OLC_SPINNER_MSG"
      sleep 0.1
    done
  } &
  _OLC_SPINNER_PID=$!
  trap "olc_spinner_stop" EXIT INT TERM
}

olc_spinner_stop() {
  [[ -n "$_OLC_SPINNER_PID" ]] || return 0
  kill "$_OLC_SPINNER_PID" 2>/dev/null || true
  wait "$_OLC_SPINNER_PID" 2>/dev/null || true
  _OLC_SPINNER_PID=""
  [[ -t 1 ]] && printf "\r\033[K"
}

olc_spinner_ok() {
  olc_spinner_stop
  olc_print_ok "$_OLC_SPINNER_MSG"
}

olc_spinner_fail() {
  olc_spinner_stop
  olc_print_fail "$_OLC_SPINNER_MSG"
}

# Progress bar
olc_progress_bar() {
  local current="$1" total="$2" width="${3:-40}"
  local percent=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))

  printf "${_C_CYAN}["
  printf "%${filled}s" | tr ' ' '█'
  printf "%${empty}s" | tr ' ' '░'
  printf "]${_C_RESET} ${_C_BOLD}%3d%%${_C_RESET} ${_C_DIM}(%d/%d)${_C_RESET}\n" "$percent" "$current" "$total"
}

# Timed execution with progress
olc_run_with_progress() {
  local label="$1"
  shift
  local interval="${OLC_PROGRESS_INTERVAL:-10}"
  local started elapsed

  olc_spinner_start "$label"
  started="$(date +%s)"

  if "$@"; then
    elapsed=$(( $(date +%s) - started ))
    olc_spinner_stop
    olc_print_ok "$label ${_C_DIM}(${elapsed}с)${_C_RESET}"
    return 0
  else
    local rc=$?
    elapsed=$(( $(date +%s) - started ))
    olc_spinner_stop
    olc_print_fail "$label ${_C_DIM}(${elapsed}с, код ${rc})${_C_RESET}"
    return "$rc"
  fi
}

# Quiet execution with log file
olc_run_quiet() {
  local label="$1"
  local log_file="$2"
  shift 2
  local started elapsed rc

  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

  if [[ "${OLC_VERBOSE_INSTALL:-0}" == "1" ]]; then
    olc_print_step "$label"
    "$@"
    return
  fi

  olc_spinner_start "$label"
  olc_print_info "Лог: ${_C_CYAN}${log_file}${_C_RESET}"

  started="$(date +%s)"
  rc=0
  "$@" >>"$log_file" 2>&1 || rc=$?
  elapsed=$(( $(date +%s) - started ))

  if [[ "$rc" -eq 0 ]]; then
    olc_spinner_stop
    olc_print_ok "$label ${_C_DIM}(${elapsed}с)${_C_RESET}"
  else
    olc_spinner_stop
    olc_print_fail "$label ${_C_DIM}(${elapsed}с, код ${rc})${_C_RESET}"
    olc_print_warn "Последние строки лога:"
    tail -20 "$log_file" 2>/dev/null | sed 's/^/  /' >&2 || true
  fi
  return "$rc"
}

# Summary box
olc_print_summary() {
  local title="$1"
  shift
  echo -e "\n${_C_BOLD}${_C_GREEN}╔═══════════════════════════════════════════════════════════╗${_C_RESET}"
  printf "${_C_BOLD}${_C_GREEN}║${_C_RESET} ${_C_BOLD}%-57s${_C_RESET} ${_C_BOLD}${_C_GREEN}║${_C_RESET}\n" "$title"
  echo -e "${_C_BOLD}${_C_GREEN}╠═══════════════════════════════════════════════════════════╣${_C_RESET}"
  while [[ $# -gt 0 ]]; do
    printf "${_C_BOLD}${_C_GREEN}║${_C_RESET} %-57s ${_C_BOLD}${_C_GREEN}║${_C_RESET}\n" "$1"
    shift
  done
  echo -e "${_C_BOLD}${_C_GREEN}╚═══════════════════════════════════════════════════════════╝${_C_RESET}\n"
}

# Error box
olc_print_error_box() {
  local title="$1"
  shift
  echo -e "\n${_C_BOLD}${_C_RED}╔═══════════════════════════════════════════════════════════╗${_C_RESET}" >&2
  printf "${_C_BOLD}${_C_RED}║${_C_RESET} ${_C_BOLD}%-57s${_C_RESET} ${_C_BOLD}${_C_RED}║${_C_RESET}\n" "$title" >&2
  echo -e "${_C_BOLD}${_C_RED}╠═══════════════════════════════════════════════════════════╣${_C_RESET}" >&2
  while [[ $# -gt 0 ]]; do
    printf "${_C_BOLD}${_C_RED}║${_C_RESET} %-57s ${_C_BOLD}${_C_RED}║${_C_RESET}\n" "$1" >&2
    shift
  done
  echo -e "${_C_BOLD}${_C_RED}╚═══════════════════════════════════════════════════════════╝${_C_RESET}\n" >&2
}

# Component status
olc_print_component_status() {
  local name="$1" status="$2"
  local icon color
  case "$status" in
    active|running|enabled|ok|connected)
      icon="${_ICON_OK}" color="${_C_GREEN}"
      ;;
    inactive|stopped|disabled|fail|disconnected)
      icon="${_ICON_FAIL}" color="${_C_RED}"
      ;;
    *)
      icon="${_ICON_WARN}" color="${_C_YELLOW}"
      ;;
  esac
  printf "  ${color}${icon}${_C_RESET} %-15s ${color}%s${_C_RESET}\n" "$name" "$status"
}

# Disk space warning
olc_print_disk_warning() {
  local path="$1" avail="$2" used_pct="$3"
  olc_print_warn "Мало места на ${_C_BOLD}${path}${_C_RESET}: ${_C_BOLD}${avail} МБ${_C_RESET} свободно (${_C_BOLD}${used_pct}%${_C_RESET} занято)"
}

# Command hint
olc_print_command() {
  local cmd="$1"
  echo -e "  ${_C_DIM}\$${_C_RESET} ${_C_CYAN}${cmd}${_C_RESET}"
}
