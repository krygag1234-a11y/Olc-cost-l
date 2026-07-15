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

# Progress bar — ОДИН персистентный spinner на весь процесс установки/обновления.
# Архитектура:
#   - spinner (фоновый процесс) рисует бар нижней строкой и живёт МЕЖДУ шагами;
#   - шаги публикуют "curr total name" в IPC-файл progress (атомарно, через mv);
#   - все сообщения идут в очередь IPC/messages — spinner печатает их НАД баром
#     (бар остаётся статичной нижней строкой, ничего не накладывается);
#   - подзадачи (IPC/substep) отображаются dim-текстом справа от имени шага.
_OLCRTC_PROGRESS_PID=""
_OLCRTC_PROGRESS_CURR=0
_OLCRTC_PROGRESS_TOTAL=0
_OLCRTC_PROGRESS_STEP_NAME=""
: "${_OLCRTC_PROGRESS_IPC_DIR:=}"
: "${_OLCRTC_PROGRESS_SUBSTEP_FILE:=}"
: "${_OLCRTC_PROGRESS_SIMPLE_FLAG:=}"
: "${_OLCRTC_PROGRESS_ACTIVE:=0}"
: "${_OLCRTC_PROGRESS_SIMPLE:=0}"  # Статичный режим для не-TTY
: "${_OLCRTC_PROGRESS_OUT:=}"      # "" = stdout (TTY), иначе /dev/tty
_OLCRTC_PROGRESS_IPC_OWNER=0

# IPC создаёт только родитель state machine. Вложенный bash сохраняет пути из environment.
_olc_progress_ipc_init() {
  if [[ -n "$_OLCRTC_PROGRESS_SUBSTEP_FILE" && -n "$_OLCRTC_PROGRESS_SIMPLE_FLAG" ]]; then
    # Унаследованные пути — валидировать, что родительский IPC-каталог содержит их.
    if [[ -n "$_OLCRTC_PROGRESS_IPC_DIR" ]]; then
      local resolved_substep resolved_simple
      resolved_substep="$(cd "$(dirname "$_OLCRTC_PROGRESS_SUBSTEP_FILE")" && pwd)/$(basename "$_OLCRTC_PROGRESS_SUBSTEP_FILE")" 2>/dev/null || return 1
      resolved_simple="$(cd "$(dirname "$_OLCRTC_PROGRESS_SIMPLE_FLAG")" && pwd)/$(basename "$_OLCRTC_PROGRESS_SIMPLE_FLAG")" 2>/dev/null || return 1
      [[ "$resolved_substep" == "$_OLCRTC_PROGRESS_IPC_DIR"/* ]] || return 1
      [[ "$resolved_simple" == "$_OLCRTC_PROGRESS_IPC_DIR"/* ]] || return 1
    fi
    return 0
  fi

  local old_umask
  old_umask="$(umask)"
  umask 077
  _OLCRTC_PROGRESS_IPC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/olcrtc-progress.XXXXXX")" || {
    umask "$old_umask"
    return 1
  }
  umask "$old_umask"
  _OLCRTC_PROGRESS_SUBSTEP_FILE="$_OLCRTC_PROGRESS_IPC_DIR/substep"
  _OLCRTC_PROGRESS_SIMPLE_FLAG="$_OLCRTC_PROGRESS_IPC_DIR/simple"
  _OLCRTC_PROGRESS_IPC_OWNER=1
}

# Атомарная публикация "curr total name" для spinner (mv атомарен в пределах fs).
# Фикс «100% (шаг 1/1)»: spinner никогда не видит пустой/усечённый файл.
_olc_progress_publish() {
  local curr="$1" total="$2" name="${3:-}"
  [[ -n "$_OLCRTC_PROGRESS_IPC_DIR" && -d "$_OLCRTC_PROGRESS_IPC_DIR" ]] || return 0
  printf '%s %s %s\n' "$curr" "$total" "$name" > "$_OLCRTC_PROGRESS_IPC_DIR/progress.tmp" 2>/dev/null || return 0
  mv -f "$_OLCRTC_PROGRESS_IPC_DIR/progress.tmp" "$_OLCRTC_PROGRESS_IPC_DIR/progress" 2>/dev/null || true
}

# printf в цель отрисовки бара (stdout-TTY или /dev/tty)
_olc_progress_print() {
  # shellcheck disable=SC2059
  if [[ -n "${_OLCRTC_PROGRESS_OUT:-}" ]]; then
    printf "$@" > "$_OLCRTC_PROGRESS_OUT" 2>/dev/null || printf "$@"
  else
    printf "$@"
  fi
}

# Публичная функция: сообщение «под прогресс-баром» (с отступом «→»).
# При активном animated-баре — в очередь (spinner напечатает НАД баром,
# бар останется нижней строкой); иначе — обычная строка с отступом.
# Использовать вместо голых echo в подзадачах шагов.
olc_progress_msg() {
  local msg="$*"
  [[ -n "$msg" ]] || return 0
  if [[ -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" && -f "${_OLCRTC_PROGRESS_IPC_DIR}/spinner" ]]; then
    printf '%s\n' "$msg" >> "${_OLCRTC_PROGRESS_IPC_DIR}/messages" 2>/dev/null && return 0
  fi
  # FD 3 — обход редиректа шага в лог (как в _olc_substep)
  if { true >&3; } 2>/dev/null; then
    printf '  → %s\n' "$msg" >&3
  else
    printf '  → %s\n' "$msg"
  fi
}

_olc_progress_step_cleanup() {
  # TTY-режим: spinner живёт между шагами — флаги не сбрасывать
  if [[ -n "$_OLCRTC_PROGRESS_PID" ]] && kill -0 "$_OLCRTC_PROGRESS_PID" 2>/dev/null; then
    return 0
  fi
  _OLCRTC_PROGRESS_SIMPLE=0
  _OLCRTC_PROGRESS_ACTIVE=0
}

_olc_progress_cleanup() {
  local rc="${1:-$?}"
  _olc_progress_stop 2>/dev/null || true
  _olc_progress_step_cleanup
  if [[ "$_OLCRTC_PROGRESS_IPC_OWNER" == "1" && -n "$_OLCRTC_PROGRESS_IPC_DIR" ]]; then
    rm -f "$_OLCRTC_PROGRESS_IPC_DIR"/messages "$_OLCRTC_PROGRESS_IPC_DIR"/consumed \
      "$_OLCRTC_PROGRESS_IPC_DIR"/progress "$_OLCRTC_PROGRESS_IPC_DIR"/progress.tmp \
      "$_OLCRTC_PROGRESS_IPC_DIR"/spinner "$_OLCRTC_PROGRESS_IPC_DIR"/simple \
      "$_OLCRTC_PROGRESS_IPC_DIR"/substep 2>/dev/null || true
    rmdir "$_OLCRTC_PROGRESS_IPC_DIR" 2>/dev/null || true
  fi
  return "$rc"
}

# Функция для отчёта о подзадаче (вызывается из agent-bootstrap.sh и др.)
_olc_substep() {
  local substep_name="$1"

  # Записать в файл для чтения анимацией (TTY mode) или вывода (simple mode)
  if [[ -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" ]]; then
    local curr total previous_name
    read curr total previous_name < "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null || { curr=0; total=0; }
    curr=$(( curr + 1 ))
    echo "$curr $total $substep_name" > "$_OLCRTC_PROGRESS_SUBSTEP_FILE"

    # Если simple mode — сразу печатать статичный прогресс через FD 3 (обход редиректа в лог)
    # Проверка через файл-флаг вместо переменной окружения
    if [[ -f "$_OLCRTC_PROGRESS_SIMPLE_FLAG" && "$total" -gt 0 ]]; then
      local percent=$(( curr * 100 / total ))
      (( percent > 100 )) && percent=100
      # FD 3 для обхода редиректа >>/var/log/olcrtc-bootstrap-patches.log 2>&1
      if { true >&3; } 2>/dev/null; then
        printf "  → %s (%d/%d, %d%%)\n" "$substep_name" "$curr" "$total" "$percent" >&3
      else
        printf "  → %s (%d/%d, %d%%)\n" "$substep_name" "$curr" "$total" "$percent"
      fi
    fi
  fi
}

# Сбросить счётчик подзадач (вызывается в начале state_step)
_olc_substep_reset() {
  local total="${1:-0}"
  _olc_progress_ipc_init || return 1
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

# Запуск/обновление анимированного прогресс-бара (вызывается в начале state_step).
# Spinner запускается ОДИН раз и живёт до state_finish / ошибки —
# последующие вызовы только обновляют IPC (шаг, имя, сброс подзадач).
_olc_progress_start() {
  local step_name="$1"
  _olc_progress_ipc_init || return 1
  _OLCRTC_PROGRESS_STEP_NAME="$step_name"

  # Куда рисовать бар: stdout (если TTY), иначе /dev/tty (SSH/sudo-цепочки,
  # где stdout не TTY, но управляющий терминал доступен). Нет ни того ни
  # другого (CI, pipe, cron) или OLC_NO_SPINNER=1 → simple mode.
  local out="-"
  if [[ "${OLC_NO_SPINNER:-0}" == "1" ]]; then
    out="-"
  elif [[ -t 1 ]]; then
    out=""
  elif { : >/dev/tty; } 2>/dev/null; then
    out="/dev/tty"
  fi

  if [[ "$out" == "-" ]]; then
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

  _OLCRTC_PROGRESS_OUT="$out"
  _OLCRTC_PROGRESS_SIMPLE=0
  _OLCRTC_PROGRESS_ACTIVE=1
  export _OLCRTC_PROGRESS_ACTIVE
  export _OLCRTC_PROGRESS_SIMPLE

  # Опубликовать состояние шага ДО первого кадра spinner —
  # фикс сброса на «100% (шаг 1/1)» между шагами.
  echo "0 0" > "$_OLCRTC_PROGRESS_SUBSTEP_FILE"
  _olc_progress_publish "$_OLCRTC_STEP_NUM" "$OLCRTC_TOTAL_STEPS" "$step_name"

  # ОДИН прогресс-бар на весь процесс: если spinner уже работает —
  # IPC обновлён, ничего не перезапускаем (нет дублирования бара).
  if [[ -n "$_OLCRTC_PROGRESS_PID" ]] && kill -0 "$_OLCRTC_PROGRESS_PID" 2>/dev/null; then
    return 0
  fi

  : > "$_OLCRTC_PROGRESS_IPC_DIR/messages"
  echo 0 > "$_OLCRTC_PROGRESS_IPC_DIR/consumed"
  # Флаг «animated spinner работает» — по нему olc_progress_msg/olc_state_line
  # решают, отправлять ли сообщения в очередь (виден и вложенным процессам).
  touch "$_OLCRTC_PROGRESS_IPC_DIR/spinner"

  # Запустить фоновый процесс анимации
  (
    # Игнорировать SIGTERM чтобы не ломать exit code родителя
    trap '' TERM
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    # Кэш последних валидных значений — файл может быть недоступен долю секунды
    local curr="$_OLCRTC_STEP_NUM" total="$OLCRTC_TOTAL_STEPS" name="$step_name"
    local consumed=0
    local msg_file="$_OLCRTC_PROGRESS_IPC_DIR/messages"
    local out_dev="$_OLCRTC_PROGRESS_OUT"

    _sp() {
      # shellcheck disable=SC2059
      if [[ -n "$out_dev" ]]; then printf "$@" > "$out_dev"; else printf "$@"; fi
    }

    while true; do
      # 1) Актуальный шаг из IPC; невалидные чтения игнорируем (кэш)
      local new_curr="" new_total="" new_name=""
      if [[ -f "$_OLCRTC_PROGRESS_IPC_DIR/progress" ]]; then
        read -r new_curr new_total new_name < "$_OLCRTC_PROGRESS_IPC_DIR/progress" 2>/dev/null || true
        if [[ "$new_curr" =~ ^[0-9]+$ && "$new_total" =~ ^[0-9]+$ ]] && (( new_total > 0 )); then
          curr="$new_curr"
          total="$new_total"
          [[ -n "$new_name" ]] && name="$new_name"
        fi
      fi
      (( total > 0 )) || total=1
      (( curr > total )) && curr="$total"
      (( curr < 1 )) && curr=1

      # Требование UX: прогресс = шаг/всего (9% → 18% → 27% → … → 100%)
      local percent=$(( curr * 100 / total ))
      (( percent > 100 )) && percent=100

      # 2) Имя текущей подзадачи (dim-текст справа от имени шага)
      local s_curr=0 s_total=0 s_name=""
      if [[ -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" ]]; then
        read -r s_curr s_total s_name < "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null || true
      fi

      # 3) Новые сообщения из очереди печатаем строками НАД баром —
      #    бар всегда остаётся нижней строкой, наложений нет.
      if [[ -f "$msg_file" ]]; then
        local lines
        lines=$(wc -l < "$msg_file" 2>/dev/null) || lines=0
        [[ "$lines" =~ ^[0-9]+$ ]] || lines=0
        if (( lines > consumed )); then
          _sp "\r\033[K"
          local n=0 line=""
          while IFS= read -r line; do
            n=$(( n + 1 ))
            (( n <= consumed )) && continue
            (( n > lines )) && break
            _sp "  \033[2m→ %s\033[0m\n" "$line"
          done < "$msg_file"
          consumed="$lines"
          echo "$consumed" > "$_OLCRTC_PROGRESS_IPC_DIR/consumed" 2>/dev/null || true
        fi
      fi

      # 4) Отрисовать бар (одна строка, перерисовка на месте)
      local width=30
      local filled=$(( width * percent / 100 ))
      local empty=$(( width - filled ))
      local bar=""
      local j
      for ((j=0; j<filled; j++)); do bar+="█"; done
      for ((j=0; j<empty; j++)); do bar+="░"; done

      local substep_display=""
      if [[ -n "$s_name" ]]; then
        substep_display=$( printf ' \033[2m→ %s\033[0m' "$s_name" )
      fi

      _sp "\r\033[K\033[36m%s\033[0m [%s] %d%% \033[2m(шаг %d/%d)\033[0m %s%s" \
        "${frames[$i]}" "$bar" "$percent" "$curr" "$total" "$name" "$substep_display"

      i=$(( (i + 1) % ${#frames[@]} ))
      sleep 0.1
    done
  ) &
  _OLCRTC_PROGRESS_PID=$!
}

# Дослать сообщения, которые spinner не успел напечатать (вызывать ПОСЛЕ kill)
_olc_progress_drain_messages() {
  local msg_file="$_OLCRTC_PROGRESS_IPC_DIR/messages"
  [[ -f "$msg_file" ]] || return 0
  local consumed=0
  if [[ -f "$_OLCRTC_PROGRESS_IPC_DIR/consumed" ]]; then
    read -r consumed < "$_OLCRTC_PROGRESS_IPC_DIR/consumed" 2>/dev/null || consumed=0
  fi
  [[ "$consumed" =~ ^[0-9]+$ ]] || consumed=0
  local n=0 line=""
  while IFS= read -r line; do
    n=$(( n + 1 ))
    (( n <= consumed )) && continue
    _olc_progress_print "  \033[2m→ %s\033[0m\n" "$line"
  done < "$msg_file"
  : > "$msg_file"
  echo 0 > "$_OLCRTC_PROGRESS_IPC_DIR/consumed" 2>/dev/null || true
}

# Завершение шага БЕЗ остановки spinner (TTY) / статичное закрытие (simple).
_olc_progress_step_end() {
  if [[ "$_OLCRTC_PROGRESS_SIMPLE" == "1" ]]; then
    _OLCRTC_PROGRESS_ACTIVE=0
    # НЕ сбрасываем _OLCRTC_PROGRESS_SIMPLE здесь — нужен для вывода результата в _state_log
    # НЕ удаляем файл-флаг — нужен для olc_state_line()
    rm -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null
    return 0
  fi
  # TTY: spinner продолжает работать; сбросить только отображение подзадачи
  if [[ -n "$_OLCRTC_PROGRESS_SUBSTEP_FILE" ]]; then
    echo "0 0" > "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null || true
  fi
}

# Полная остановка анимации (ошибка шага, state_finish, trap)
_olc_progress_stop() {
  # Simple mode — только очистка
  if [[ "$_OLCRTC_PROGRESS_SIMPLE" == "1" ]]; then
    _OLCRTC_PROGRESS_ACTIVE=0
    rm -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null
    return 0
  fi

  [[ -z "$_OLCRTC_PROGRESS_PID" ]] && return 0
  # Снять флаг ПЕРВЫМ — новые сообщения пойдут напрямую, минуя очередь
  rm -f "$_OLCRTC_PROGRESS_IPC_DIR/spinner" 2>/dev/null
  kill -9 "$_OLCRTC_PROGRESS_PID" 2>/dev/null
  wait "$_OLCRTC_PROGRESS_PID" 2>/dev/null || true  # ignore exit code 137 from SIGKILL
  _OLCRTC_PROGRESS_PID=""
  _OLCRTC_PROGRESS_ACTIVE=0
  # Очистить строку бара и дослать несведённые сообщения
  _olc_progress_print "\r\033[K"
  _olc_progress_drain_messages
  # Удалить файл обмена данными
  rm -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null
}

# Финальный аккорд: остановить spinner и напечатать закреплённый бар 100%.
_olc_progress_finish() {
  [[ "$_OLCRTC_PROGRESS_SIMPLE" == "1" ]] && return 0
  [[ -z "$_OLCRTC_PROGRESS_PID" ]] && return 0
  # Последние валидные curr/total из IPC
  local curr="$_OLCRTC_STEP_NUM" total="$OLCRTC_TOTAL_STEPS"
  if [[ -f "$_OLCRTC_PROGRESS_IPC_DIR/progress" ]]; then
    local f_curr="" f_total="" f_name=""
    read -r f_curr f_total f_name < "$_OLCRTC_PROGRESS_IPC_DIR/progress" 2>/dev/null || true
    if [[ "$f_curr" =~ ^[0-9]+$ && "$f_total" =~ ^[0-9]+$ ]] && (( f_total > 0 )); then
      curr="$f_curr"
      total="$f_total"
    fi
  fi
  _olc_progress_stop
  (( total > 0 )) || total=1
  (( curr > total )) && curr="$total"
  local bar=""
  local j
  for ((j=0; j<30; j++)); do bar+="█"; done
  _olc_progress_print "\033[32m✓\033[0m [%s] 100%% \033[2m(шаг %d/%d)\033[0m завершено\n" \
    "$bar" "$curr" "$total"
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
  # Graceful degradation: прогресс-бар опционален, не блокирует install при mktemp failure.
  _olc_progress_ipc_init || {
    export _OLCRTC_PROGRESS_SIMPLE=1
    export _OLCRTC_PROGRESS_ACTIVE=0
  }
  mkdir -p "$OLCRTC_STATE_DIR"
  if [[ "${1:-}" == "--fresh" || "$OLCRTC_FRESH" == "1" ]]; then
    rm -f "$OLCRTC_STATE_FILE"
  fi
  if [[ ! -f "$OLCRTC_STATE_FILE" ]]; then
    printf '{"started":"%s","last_ok":null,"history":[],"failed":null}\n' \
      "$(date -u +%FT%TZ)" > "$OLCRTC_STATE_FILE"
  fi
  # Установить trap для очистки анимации и parent-owned IPC при прерывании
  trap '_olc_progress_cleanup $?' EXIT
  trap '_olc_progress_cleanup 130; exit 130' INT
  trap '_olc_progress_cleanup 143; exit 143' TERM
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
    # Учесть пропуск в прогрессе, чтобы шаги/проценты не съезжали
    _olc_progress_publish "$_OLCRTC_STEP_NUM" "$OLCRTC_TOTAL_STEPS" "$name"
    _state_log "skip $name (already done — resume)"
    return 0
  fi

  # Обновить счётчик для анимации
  _OLCRTC_PROGRESS_CURR="$_OLCRTC_STEP_NUM"
  _OLCRTC_PROGRESS_TOTAL="$OLCRTC_TOTAL_STEPS"

  # Запустить/обновить прогресс и экспортировать IPC-контракт для подпроцессов.
  _olc_progress_start "$name"
  export _OLCRTC_PROGRESS_IPC_DIR
  export _OLCRTC_PROGRESS_SUBSTEP_FILE
  export _OLCRTC_PROGRESS_SIMPLE_FLAG
  export _OLCRTC_PROGRESS_ACTIVE
  export _OLCRTC_PROGRESS_SIMPLE
  export -f _olc_progress_ipc_init 2>/dev/null || true
  export -f _olc_substep 2>/dev/null || true
  export -f _olc_substep_reset 2>/dev/null || true
  export -f _olc_progress_publish 2>/dev/null || true
  export -f olc_progress_msg 2>/dev/null || true

  local started; started=$(date +%s)
  local rc=0
  "$@" || rc=$?
  local dur=$(( $(date +%s) - started ))

  if [[ $rc -eq 0 ]]; then
    # Spinner НЕ останавливаем — бар остаётся на месте, результат уходит под бар
    _olc_progress_step_end
    _state_log "✓ $name (${dur}s)"
    _olc_progress_step_cleanup
    _state_record_ok "$name"
    return 0
  fi
  # Ошибка: полностью остановить анимацию, чтобы сообщения не наложились на бар
  _olc_progress_stop
  _state_log "✗ $name (rc=$rc, ${dur}s)"
  _olc_progress_step_cleanup
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
  # Закрыть прогресс-бар финальной строкой «✓ [████] 100% завершено»
  _olc_progress_finish
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
