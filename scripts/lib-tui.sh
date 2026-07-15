#!/usr/bin/env bash
# Rich TUI library: colors, animations, spinners, interactive menus, progress bars
[[ -n "${_OLC_TUI_LOADED:-}" ]] && return 0
_OLC_TUI_LOADED=1

# ============================================================================
# COLORS & STYLES
# ============================================================================

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
  # Basic colors
  TUI_RESET='\033[0m'
  TUI_BOLD='\033[1m'
  TUI_DIM='\033[2m'
  TUI_ITALIC='\033[3m'
  TUI_UNDERLINE='\033[4m'
  TUI_BLINK='\033[5m'
  TUI_REVERSE='\033[7m'
  
  # Foreground colors
  TUI_BLACK='\033[30m'
  TUI_RED='\033[31m'
  TUI_GREEN='\033[32m'
  TUI_YELLOW='\033[33m'
  TUI_BLUE='\033[34m'
  TUI_MAGENTA='\033[35m'
  TUI_CYAN='\033[36m'
  TUI_WHITE='\033[37m'
  TUI_GRAY='\033[90m'
  TUI_BRIGHT_RED='\033[91m'
  TUI_BRIGHT_GREEN='\033[92m'
  TUI_BRIGHT_YELLOW='\033[93m'
  TUI_BRIGHT_BLUE='\033[94m'
  TUI_BRIGHT_MAGENTA='\033[95m'
  TUI_BRIGHT_CYAN='\033[96m'
  TUI_BRIGHT_WHITE='\033[97m'
  
  # Background colors
  TUI_BG_BLACK='\033[40m'
  TUI_BG_RED='\033[41m'
  TUI_BG_GREEN='\033[42m'
  TUI_BG_YELLOW='\033[43m'
  TUI_BG_BLUE='\033[44m'
  TUI_BG_MAGENTA='\033[45m'
  TUI_BG_CYAN='\033[46m'
  TUI_BG_WHITE='\033[47m'
else
  TUI_RESET='' TUI_BOLD='' TUI_DIM='' TUI_ITALIC='' TUI_UNDERLINE=''
  TUI_BLINK='' TUI_REVERSE=''
  TUI_BLACK='' TUI_RED='' TUI_GREEN='' TUI_YELLOW='' TUI_BLUE=''
  TUI_MAGENTA='' TUI_CYAN='' TUI_WHITE='' TUI_GRAY=''
  TUI_BRIGHT_RED='' TUI_BRIGHT_GREEN='' TUI_BRIGHT_YELLOW=''
  TUI_BRIGHT_BLUE='' TUI_BRIGHT_MAGENTA='' TUI_BRIGHT_CYAN='' TUI_BRIGHT_WHITE=''
  TUI_BG_BLACK='' TUI_BG_RED='' TUI_BG_GREEN='' TUI_BG_YELLOW=''
  TUI_BG_BLUE='' TUI_BG_MAGENTA='' TUI_BG_CYAN='' TUI_BG_WHITE=''
fi

# ============================================================================
# CURSOR CONTROL
# ============================================================================

tui_cursor_hide() { [[ -t 1 ]] && echo -ne '\033[?25l'; return 0; }
tui_cursor_show() { [[ -t 1 ]] && echo -ne '\033[?25h'; return 0; }
tui_cursor_save() { [[ -t 1 ]] && echo -ne '\033[s'; return 0; }
tui_cursor_restore() { [[ -t 1 ]] && echo -ne '\033[u'; return 0; }
tui_cursor_up() { [[ -t 1 ]] && echo -ne "\033[${1:-1}A"; return 0; }
tui_cursor_down() { [[ -t 1 ]] && echo -ne "\033[${1:-1}B"; return 0; }
tui_cursor_right() { [[ -t 1 ]] && echo -ne "\033[${1:-1}C"; return 0; }
tui_cursor_left() { [[ -t 1 ]] && echo -ne "\033[${1:-1}D"; return 0; }
tui_cursor_to() { [[ -t 1 ]] && echo -ne "\033[${1:-1};${2:-1}H"; return 0; }
tui_cursor_col() { [[ -t 1 ]] && echo -ne "\033[${1:-1}G"; return 0; }

# Clear screen functions
tui_clear() { [[ -t 1 ]] && echo -ne '\033[2J\033[H'; return 0; }
tui_clear_line() { [[ -t 1 ]] && echo -ne '\033[2K\r'; return 0; }
tui_clear_to_end() { [[ -t 1 ]] && echo -ne '\033[K'; return 0; }

# Get terminal size
tui_term_width() { tput cols 2>/dev/null || echo 80; }
tui_term_height() { tput lines 2>/dev/null || echo 24; }

# Spinners
_TUI_SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
_TUI_SPINNER_PID=""
_TUI_SPINNER_MSG=""

tui_spinner_start() {
  local msg="${1:-Loading}"
  _TUI_SPINNER_MSG="$msg"
  # Skip spinner if OLC_NO_SPINNER=1 or not a TTY
  if [[ "${OLC_NO_SPINNER:-0}" == "1" ]] || [[ ! -t 1 ]]; then
    echo "→ $msg..."
    return
  fi
  tui_cursor_hide
  (
    local i=0
    while true; do
      echo -ne "\r${TUI_CYAN}${_TUI_SPINNER_FRAMES[$i]}${TUI_RESET} ${msg}..."
      i=$(( (i + 1) % ${#_TUI_SPINNER_FRAMES[@]} ))
      sleep 0.1
    done
  ) &
  _TUI_SPINNER_PID=$!
}

tui_spinner_stop() {
  [[ -n "$_TUI_SPINNER_PID" ]] && kill "$_TUI_SPINNER_PID" 2>/dev/null && wait "$_TUI_SPINNER_PID" 2>/dev/null
  _TUI_SPINNER_PID=""
  if [[ -t 1 ]]; then tui_clear_line; tui_cursor_show; fi
  return 0
}

tui_spinner_ok() {
  tui_spinner_stop
  echo -e "${TUI_GREEN}✓${TUI_RESET} ${_TUI_SPINNER_MSG}"
}

tui_spinner_fail() {
  tui_spinner_stop
  echo -e "${TUI_RED}✗${TUI_RESET} ${_TUI_SPINNER_MSG}"
}

# Progress bar
tui_progress_bar() {
  local current="$1"
  local total="$2"
  local width="${3:-40}"
  local percent=$(( current * 100 / total ))
  local filled=$(( width * current / total ))
  local empty=$(( width - filled ))
  
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  
  echo -ne "\r${TUI_CYAN}[${bar}]${TUI_RESET} ${percent}%"
  [[ "$current" -eq "$total" ]] && echo ""
}

# Interactive menu
tui_menu() {
  local title="$1"
  shift
  local options=("$@")
  local selected=0
  local key=""
  
  [[ ! -t 0 ]] && { echo "0"; return 0; }

  tui_cursor_hide
  local _tui_old_trap
  _tui_old_trap="$(trap -p EXIT 2>/dev/null || true)"
  trap 'tui_cursor_show' EXIT

  # Save cursor position, draw menu below current output (no screen clear)
  echo ""
  local _menu_start_line
  _menu_start_line=$(( ${#options[@]} + 3 ))

  while true; do
    # Move cursor to menu start and redraw (don't clear entire screen)
    tui_cursor_up "$_menu_start_line" 2>/dev/null || true
    echo -e "\033[K${TUI_BOLD}${TUI_CYAN}${title}${TUI_RESET}"
    echo -e "\033[K"
    
    for i in "${!options[@]}"; do
      if [[ "$i" -eq "$selected" ]]; then
        echo -e "\033[K  ${TUI_BG_CYAN}${TUI_BLACK} $((i+1)). ${options[$i]} ${TUI_RESET}"
      else
        echo -e "\033[K  ${TUI_DIM} $((i+1)). ${options[$i]}${TUI_RESET}"
      fi
    done
    echo -e "\033[K"

    IFS= read -rsn1 key </dev/tty 2>/dev/null || break
    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.1 key </dev/tty 2>/dev/null || true
        case "$key" in
          '[A') selected=$(( selected > 0 ? selected - 1 : ${#options[@]} - 1 )) ;;
          '[B') selected=$(( (selected + 1) % ${#options[@]} )) ;;
        esac
        ;;
      '') break ;;
    esac
  done

  tui_cursor_show
  # Restore previous EXIT trap
  if [[ -n "$_tui_old_trap" ]]; then
    eval "$_tui_old_trap"
  else
    trap - EXIT
  fi
  echo "$selected"
}

# Box drawing
tui_box() {
  local width="${1:-60}"
  local text="${2:-}"
  local top="╔$(printf '═%.0s' $(seq 1 $((width-2))))╗"
  local bottom="╚$(printf '═%.0s' $(seq 1 $((width-2))))╝"
  local empty="║$(printf ' %.0s' $(seq 1 $((width-2))))║"
  
  echo -e "${TUI_CYAN}${top}${TUI_RESET}"
  if [[ -n "$text" ]]; then
    local pad=$(( (width - ${#text} - 2) / 2 ))
    printf "${TUI_CYAN}║${TUI_RESET}%*s${TUI_BOLD}%s${TUI_RESET}%*s${TUI_CYAN}║${TUI_RESET}\n" \
      $pad "" "$text" $((width - ${#text} - pad - 2)) ""
  else
    echo -e "$empty"
  fi
  echo -e "${TUI_CYAN}${bottom}${TUI_RESET}"
}

tui_header() {
  local text="$1"
  local width=$(tui_term_width)
  tui_box "$width" "$text"
}

# Gradient text (simple simulation)
tui_gradient() {
  local text="$1"
  local colors=("${TUI_BLUE}" "${TUI_CYAN}" "${TUI_GREEN}" "${TUI_YELLOW}" "${TUI_RED}")
  local len=${#text}
  local step=$(( len / ${#colors[@]} + 1 ))
  
  for ((i=0; i<len; i++)); do
    local color_idx=$(( i / step ))
    [[ $color_idx -ge ${#colors[@]} ]] && color_idx=$((${#colors[@]} - 1))
    echo -ne "${colors[$color_idx]}${text:$i:1}"
  done
  echo -e "${TUI_RESET}"
}

# Animated dots
tui_loading_dots() {
  local msg="${1:-Loading}"
  local dots=""
  for i in {1..3}; do
    echo -ne "\r${msg}${dots}   "
    dots+="."
    sleep 0.3
  done
  echo -ne "\r${msg}      \r"
}

# Log functions with icons
tui_log_info() {
  echo -e "${TUI_BLUE}ℹ${TUI_RESET} ${TUI_DIM}$*${TUI_RESET}"
}

tui_log_success() {
  echo -e "${TUI_GREEN}✓${TUI_RESET} ${TUI_GREEN}$*${TUI_RESET}"
}

tui_log_warning() {
  echo -e "${TUI_YELLOW}⚠${TUI_RESET} ${TUI_YELLOW}$*${TUI_RESET}"
}

tui_log_error() {
  echo -e "${TUI_RED}✗${TUI_RESET} ${TUI_RED}$*${TUI_RESET}" >&2
}

# Fatal error with context and exit
tui_fatal() {
  local error_msg="$1"
  local context="${2:-}"
  local hint="${3:-}"

  echo "" >&2
  echo -e "${TUI_BG_RED}${TUI_WHITE}${TUI_BOLD} ОШИБКА ${TUI_RESET}" >&2
  echo "" >&2
  echo -e "${TUI_RED}✗ $error_msg${TUI_RESET}" >&2

  if [[ -n "$context" ]]; then
    echo "" >&2
    echo -e "${TUI_YELLOW}Контекст:${TUI_RESET}" >&2
    echo -e "  ${TUI_GRAY}$context${TUI_RESET}" >&2
  fi

  if [[ -n "$hint" ]]; then
    echo "" >&2
    echo -e "${TUI_CYAN}💡 Подсказка:${TUI_RESET}" >&2
    echo -e "  ${TUI_CYAN}$hint${TUI_RESET}" >&2
  fi

  echo "" >&2
  exit 1
}

tui_log_step() {
  echo -e "${TUI_CYAN}→${TUI_RESET} $*"
}

tui_log_bullet() {
  echo -e "  ${TUI_GRAY}•${TUI_RESET} $*"
}

# Real-time log viewer
tui_tail_log() {
  local logfile="$1"
  local lines="${2:-10}"
  [[ ! -f "$logfile" ]] && { tui_log_error "Log file not found: $logfile"; return 1; }
  
  echo -e "${TUI_CYAN}═══ Логи: $logfile ═══${TUI_RESET}"
  tail -f -n "$lines" "$logfile" | while IFS= read -r line; do
    case "$line" in
      *ERROR*|*error*|*FAIL*|*fail*)
        echo -e "${TUI_RED}${line}${TUI_RESET}"
        ;;
      *WARN*|*warn*)
        echo -e "${TUI_YELLOW}${line}${TUI_RESET}"
        ;;
      *SUCCESS*|*success*|*OK*|*done*)
        echo -e "${TUI_GREEN}${line}${TUI_RESET}"
        ;;
      *)
        echo -e "${TUI_DIM}${line}${TUI_RESET}"
        ;;
    esac
  done
}

# Confirmation prompt
tui_confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-y}"
  
  if [[ ! -t 0 ]]; then
    [[ "$default" == "n" ]] && return 1
    return 0
  fi
  
  local yn_prompt="[Y/n]"
  [[ "$default" == "n" ]] && yn_prompt="[y/N]"
  
  echo -ne "${TUI_YELLOW}?${TUI_RESET} ${prompt} ${TUI_DIM}${yn_prompt}${TUI_RESET} "
  read -r response
  
  response="${response:-$default}"
  [[ "${response,,}" == "y" || "${response,,}" == "yes" || "${response,,}" == "да" ]]
}

# Input prompt
tui_input() {
  local prompt="$1"
  local default="$2"
  
  [[ -n "$default" ]] && prompt="${prompt} ${TUI_DIM}[${default}]${TUI_RESET}"
  echo -ne "${TUI_CYAN}>${TUI_RESET} ${prompt}: "
  read -r response
  echo "${response:-$default}"
}

# Banner with ASCII art
tui_banner() {
  local text="$1"
  echo -e "\n${TUI_BOLD}${TUI_CYAN}"
  echo "╔═══════════════════════════════════════════════════════════╗"
  printf "║%-59s║\n" " $text"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo -e "${TUI_RESET}\n"
}

# Divider line
tui_divider() {
  local char="${1:-─}"
  local width=$(tui_term_width)
  local line=""
  local i
  for ((i=0; i<width; i++)); do line+="$char"; done
  echo -e "${TUI_DIM}${line}${TUI_RESET}"
}

# Export all functions
export -f tui_cursor_hide tui_cursor_show tui_cursor_save tui_cursor_restore
export -f tui_cursor_up tui_cursor_down tui_cursor_left tui_cursor_right
export -f tui_cursor_to tui_cursor_col tui_clear tui_clear_line tui_clear_to_end
export -f tui_term_width tui_term_height tui_spinner_start tui_spinner_stop
export -f tui_spinner_ok tui_spinner_fail tui_progress_bar tui_menu tui_box
export -f tui_header tui_gradient tui_loading_dots tui_log_info tui_log_success
export -f tui_log_warning tui_log_error tui_log_step tui_log_bullet tui_fatal
export -f tui_tail_log tui_confirm tui_input tui_banner tui_divider

