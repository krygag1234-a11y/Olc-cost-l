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

# Публикация пути АКТИВНОГО лога подзадачи (для подробного режима Ctrl+O).
# Вызов с пустым аргументом — снять публикацию (подзадача завершена).
_olc_progress_logfile() {
  [[ -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" && -d "${_OLCRTC_PROGRESS_IPC_DIR:-}" ]] || return 0
  if [[ -n "${1:-}" ]]; then
    printf '%s\n' "$1" > "$_OLCRTC_PROGRESS_IPC_DIR/logfile.tmp" 2>/dev/null || return 0
    mv -f "$_OLCRTC_PROGRESS_IPC_DIR/logfile.tmp" "$_OLCRTC_PROGRESS_IPC_DIR/logfile" 2>/dev/null || true
    # Копилка ВСЕХ логов сессии (уникально) — для финальной сводки путей
    if ! grep -qxF -- "$1" "$_OLCRTC_PROGRESS_IPC_DIR/logpaths" 2>/dev/null; then
      printf '%s\n' "$1" >> "$_OLCRTC_PROGRESS_IPC_DIR/logpaths" 2>/dev/null || true
    fi
  else
    rm -f "$_OLCRTC_PROGRESS_IPC_DIR/logfile" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Клавиатура во время animated-бара: Ctrl+O — показать/скрыть подробный вывод
# (как в Claude CLI). Для посимвольного чтения /dev/tty переводится в
# неканонический режим; -iexten обязателен — иначе терминал сам перехватывает
# ^O как VDISCARD (flush) и байт до нас не доходит. Исходные настройки
# сохраняются и восстанавливаются в _olc_progress_stop/_olc_progress_cleanup.
# Отключить обработку клавиш: OLC_UI_KEYS=0.
_OLCRTC_TTY_STTY_SAVED=""
_olc_progress_keys_on() {
  [[ "${OLC_UI_KEYS:-1}" == "1" ]] || return 0
  [[ -z "$_OLCRTC_TTY_STTY_SAVED" ]] || return 0
  local saved
  saved="$(stty -g </dev/tty 2>/dev/null)" || return 0
  [[ -n "$saved" ]] || return 0
  if stty -icanon -echo -iexten min 0 time 0 </dev/tty 2>/dev/null; then
    _OLCRTC_TTY_STTY_SAVED="$saved"
  fi
}
_olc_progress_keys_off() {
  [[ -n "$_OLCRTC_TTY_STTY_SAVED" ]] || return 0
  stty "$_OLCRTC_TTY_STTY_SAVED" </dev/tty 2>/dev/null || true
  _OLCRTC_TTY_STTY_SAVED=""
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
  _olc_progress_keys_off 2>/dev/null || true
  _olc_progress_step_cleanup
  # Аварийный выход из полноэкранной сессии: показать журнал в основном
  # терминале (иначе ошибки исчезнут вместе с alt-screen)
  if [[ "${_OLC_UI_ALT:-0}" == "1" ]]; then
    if [[ "$rc" != "0" ]]; then
      _olc_ui_abort_dump "$rc" || true
    else
      # \033[r — сброс scroll-региона (мог остаться от подробного режима Ctrl+O)
      printf '\033[r\033[?1049l' 2>/dev/null || true
      _OLC_UI_ALT=0
    fi
  fi
  if [[ "$_OLCRTC_PROGRESS_IPC_OWNER" == "1" && -n "$_OLCRTC_PROGRESS_IPC_DIR" ]]; then
    rm -f "$_OLCRTC_PROGRESS_IPC_DIR"/messages "$_OLCRTC_PROGRESS_IPC_DIR"/consumed \
      "$_OLCRTC_PROGRESS_IPC_DIR"/progress "$_OLCRTC_PROGRESS_IPC_DIR"/progress.tmp \
      "$_OLCRTC_PROGRESS_IPC_DIR"/spinner "$_OLCRTC_PROGRESS_IPC_DIR"/simple \
      "$_OLCRTC_PROGRESS_IPC_DIR"/substep "$_OLCRTC_PROGRESS_IPC_DIR"/transcript \
      "$_OLCRTC_PROGRESS_IPC_DIR"/logfile "$_OLCRTC_PROGRESS_IPC_DIR"/logfile.tmp \
      "$_OLCRTC_PROGRESS_IPC_DIR"/verbose "$_OLCRTC_PROGRESS_IPC_DIR"/verbose_used \
      "$_OLCRTC_PROGRESS_IPC_DIR"/logpaths 2>/dev/null || true
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

  # Клавиатура (Ctrl+O — подробный вывод): включить посимвольное чтение /dev/tty
  _olc_progress_keys_on

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

    # Клавиатура: неблокирующее чтение /dev/tty (Ctrl+O = \x0f).
    # Родитель уже перевёл tty в неканонический режим (_olc_progress_keys_on).
    local kbd_fd=""
    if [[ "${OLC_UI_KEYS:-1}" == "1" ]]; then
      { exec {kbd_fd}</dev/tty; } 2>/dev/null || kbd_fd=""
    fi
    # Подробный режим (Ctrl+O): live-хвост активного лога подзадачи
    local verbose=0 vlog="" vlog_line=0
    # Ширина терминала (кэш, обновление раз в секунду) + таймер подзадачи
    local bar_cols=80 bar_cols_tick=0 sub_prev="__none__" sub_t0=0

    # Печать новых строк лога (dim, префикс «·»), без попадания в transcript
    _sp_log_lines() {
      local vline
      while IFS= read -r vline; do
        _sp '  \033[2m· %s\033[0m\n' "$vline"
      done < <(tr -d '\r' <<<"$1" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')
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
            # transcript — полный журнал напечатанных строк (для финального
            # схлопывания экрана и дампа при ошибке)
            printf '%s\n' "$line" >> "$_OLCRTC_PROGRESS_IPC_DIR/transcript" 2>/dev/null || true
          done < "$msg_file"
          consumed="$lines"
          echo "$consumed" > "$_OLCRTC_PROGRESS_IPC_DIR/consumed" 2>/dev/null || true
        fi
      fi

      # 3.5) Подробный режим (Ctrl+O): стримить новые строки активного лога
      if (( verbose )); then
        local vnew=""
        if [[ -f "$_OLCRTC_PROGRESS_IPC_DIR/logfile" ]]; then
          IFS= read -r vnew < "$_OLCRTC_PROGRESS_IPC_DIR/logfile" 2>/dev/null || vnew=""
        fi
        if [[ "$vnew" != "$vlog" ]]; then
          vlog="$vnew"
          vlog_line=0
          if [[ -n "$vlog" && -f "$vlog" ]]; then
            # Новая подзадача: стримим только СВЕЖИЕ строки (без истории файла)
            vlog_line="$(wc -l < "$vlog" 2>/dev/null)" || vlog_line=0
            [[ "$vlog_line" =~ ^[0-9]+$ ]] || vlog_line=0
            _sp '\r\033[K  \033[2m── лог: %s ──\033[0m\n' "$vlog"
          fi
        fi
        if [[ -n "$vlog" && -f "$vlog" ]]; then
          local vtotal
          vtotal="$(wc -l < "$vlog" 2>/dev/null)" || vtotal=0
          [[ "$vtotal" =~ ^[0-9]+$ ]] || vtotal=0
          if (( vtotal > vlog_line )); then
            _sp '\r\033[K'
            # не более 40 строк за кадр — терминал не «захлёбывается»
            _sp_log_lines "$(sed -n "$((vlog_line+1)),${vtotal}p" "$vlog" 2>/dev/null | tail -n 40)"
            vlog_line="$vtotal"
          fi
        fi
      fi

      # 4) Отрисовать бар (одна строка, перерисовка на месте).
      # Строка бара НЕ должна заворачиваться: перенос ломает \r\033[K-перерисовку
      # и подсчёт рядов — всё, что не влезает по ширине, обрезается.
      if (( bar_cols_tick <= 0 )); then
        bar_cols="$(_olc_ui_term_cols)"
        bar_cols_tick=10          # обновление раз в секунду (10 кадров по 0.1с)
      fi
      bar_cols_tick=$(( bar_cols_tick - 1 ))

      local width=30
      local filled=$(( width * percent / 100 ))
      local empty=$(( width - filled ))
      local bar=""
      local j
      for ((j=0; j<filled; j++)); do bar+="█"; done
      for ((j=0; j<empty; j++)); do bar+="░"; done

      # Постоянный индикатор клавиши в строке бара (T-4): подсказка ^O всегда
      # на виду, текст меняется по состоянию подробного режима.
      local ind_txt=""
      if [[ -n "$kbd_fd" ]]; then
        if (( verbose )); then ind_txt="[^O скрыть детали]"; else ind_txt="[^O детали]"; fi
      fi

      # Таймер подзадачи (T-4, шаг к ETA): сколько секунд крутится текущая
      # подзадача; появляется после 5с — видно, что длинный шаг не завис.
      if [[ "$s_name" != "$sub_prev" ]]; then
        sub_prev="$s_name"
        sub_t0="$SECONDS"
      fi
      local sub_timer=""
      if [[ -n "$s_name" ]] && (( SECONDS - sub_t0 >= 5 )); then
        sub_timer=" · $(( SECONDS - sub_t0 ))с"
      fi

      # Бюджет ширины: фикс. часть + имя шага + подзадача + индикатор
      local step_txt="(шаг ${curr}/${total})" percent_txt="${percent}%"
      local fixed=$(( 2 + width + 2 + 1 + ${#percent_txt} + 1 + ${#step_txt} + 1 ))
      local ind_vis=0
      [[ -n "$ind_txt" ]] && ind_vis=$(( ${#ind_txt} + 2 ))
      local avail=$(( bar_cols - 1 - fixed - ind_vis ))
      (( avail < 0 )) && avail=0
      local name_disp="${name:0:avail}"
      local substep_display=""
      local sub_avail=$(( avail - ${#name_disp} - 3 - ${#sub_timer} ))
      if [[ -n "$s_name" ]] && (( sub_avail >= 6 )); then
        substep_display=$( printf ' \033[2m→ %s%s\033[0m' "${s_name:0:sub_avail}" "$sub_timer" )
      fi
      local ind_disp=""
      [[ -n "$ind_txt" ]] && ind_disp=$( printf '  \033[2m%s\033[0m' "$ind_txt" )

      _sp "\r\033[K\033[36m%s\033[0m [%s] %s \033[2m%s\033[0m %s%s%s" \
        "${frames[$i]}" "$bar" "$percent_txt" "$step_txt" "$name_disp" "$substep_display" "$ind_disp"

      i=$(( (i + 1) % ${#frames[@]} ))

      # 5) Клавиатура: read с таймаутом = кадровая задержка (вместо sleep)
      local key=""
      if [[ -n "$kbd_fd" ]]; then
        IFS= read -rsn1 -t 0.1 -u "$kbd_fd" key 2>/dev/null || key=""
      else
        sleep 0.1
      fi
      if [[ "$key" == $'\x0f' ]]; then   # Ctrl+O
        if (( verbose )); then
          # ГЛОБАЛЬНОЕ закрытие: один Ctrl+O скрывает ВСЁ накопленное подробное —
          # сброс scroll-региона + полная перерисовка компактного экрана
          # (заголовок + журнал шагов). Никаких «хвостов» от прошлых логов.
          verbose=0
          rm -f "$_OLCRTC_PROGRESS_IPC_DIR/verbose" 2>/dev/null || true
          if [[ "${_OLC_UI_ALT:-0}" == "1" ]]; then
            _sp '\033[r'
            _olc_ui_redraw_compact || true
          else
            # Без alt-screen перерисовка невозможна — только разделитель
            _sp '\r\033[K  \033[2m── подробный вывод скрыт (Ctrl+O — показать) ──\033[0m\n'
          fi
        else
          verbose=1
          vlog="" vlog_line=0
          # Флаг для родителя: финал/ошибка знают, что подробный режим включён.
          # verbose_used живёт до конца сессии: финал по нему выбирает
          # детерминированный путь (перерисовка + анимация с известной строки),
          # даже если к финалу verbose уже выключен.
          : > "$_OLCRTC_PROGRESS_IPC_DIR/verbose" 2>/dev/null || true
          : > "$_OLCRTC_PROGRESS_IPC_DIR/verbose_used" 2>/dev/null || true
          if [[ "${_OLC_UI_ALT:-0}" == "1" ]]; then
            # Детерминированный старт: чистая перерисовка компактного экрана,
            # затем scroll-регион ниже шапки — верхняя панель ЗАКРЕПЛЕНА и не
            # уезжает, сколько бы логов ни стримилось.
            _olc_ui_redraw_compact || true
            local vh vtop vrow
            vh="$(_olc_ui_term_rows)"
            vtop=$(( ${_OLC_UI_HEADER_ROWS:-0} + 1 ))
            (( vtop >= vh )) && vtop=1
            vrow=$(( ${_OLC_UI_REDRAW_ROWS:-0} + 1 ))
            (( vrow > vh )) && vrow="$vh"
            (( vrow < vtop )) && vrow="$vtop"
            _sp '\033[%d;%dr\033[%d;1H' "$vtop" "$vh" "$vrow"
          fi
          _sp '\r\033[K  \033[2m── подробный вывод (Ctrl+O — скрыть) ──\033[0m\n'
          # Контекст: хвост уже накопленного лога текущей подзадачи
          # (число строк настраивается: OLC_UI_VERBOSE_TAIL, default 12)
          local vcur=""
          if [[ -f "$_OLCRTC_PROGRESS_IPC_DIR/logfile" ]]; then
            IFS= read -r vcur < "$_OLCRTC_PROGRESS_IPC_DIR/logfile" 2>/dev/null || vcur=""
          fi
          if [[ -n "$vcur" && -f "$vcur" ]]; then
            local vtail="${OLC_UI_VERBOSE_TAIL:-12}"
            [[ "$vtail" =~ ^[0-9]+$ ]] || vtail=12
            _sp_log_lines "$(tail -n "$vtail" "$vcur" 2>/dev/null)"
          fi
        fi
      fi
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
    printf '%s\n' "$line" >> "$_OLCRTC_PROGRESS_IPC_DIR/transcript" 2>/dev/null || true
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
  # Спиннер мог быть убит при АКТИВНОМ verbose (ошибка шага → рестарт спиннера
  # на следующем шаге): снять флаг «verbose сейчас включён» и сбросить
  # scroll-регион — иначе новый спиннер стартует с verbose=0 при живом флаге
  # и первый же Ctrl+O включает verbose вместо ожидаемого выключения
  # (десинхронизация тоггла на поздних шагах). verbose_used НЕ трогаем.
  if [[ -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" && -f "$_OLCRTC_PROGRESS_IPC_DIR/verbose" ]]; then
    rm -f "$_OLCRTC_PROGRESS_IPC_DIR/verbose" 2>/dev/null || true
    _olc_progress_print '\033[r'
  fi
  # Вернуть терминал в исходный режим (клавиатура Ctrl+O больше не читается)
  _olc_progress_keys_off
  # Очистить строку бара и дослать несведённые сообщения
  _olc_progress_print "\r\033[K"
  _olc_progress_drain_messages
  # Удалить файл обмена данными
  rm -f "$_OLCRTC_PROGRESS_SUBSTEP_FILE" 2>/dev/null
}

# ============================================================================
# ПОЛНОЭКРАННАЯ TUI-СЕССИЯ (alternate screen)
# ============================================================================
# Весь процесс обновления/доустановки рисуется на отдельном экране терминала
# (как vim/htop). По завершении: строки шагов схлопываются (бар анимированно
# «поднимается» вверх), экран закрывается — и в ОСНОВНОМ терминале остаётся
# только чистый финальный вывод. При ошибке alt-screen закрывается и в
# основной терминал печатается хвост журнала (ошибки не теряются).
_OLC_UI_ALT=0
_OLC_UI_TITLE=""
_OLC_UI_INFO=()
_OLC_UI_HEADER_ROWS=0

olc_ui_begin() {
  _OLC_UI_TITLE="${1:-}"
  shift || true
  _OLC_UI_INFO=("$@")
  # Подсказка про Ctrl+O — только если клавиатура реально будет читаться
  # (animated-режим возможен и /dev/tty доступен на чтение)
  if [[ "${OLC_NO_SPINNER:-0}" != "1" && "${OLC_UI_KEYS:-1}" == "1" && "${TERM:-}" != "dumb" ]] \
     && { : </dev/tty; } 2>/dev/null; then
    _OLC_UI_INFO+=("Ctrl+O — показать/скрыть подробный вывод")
  fi
  if [[ -t 1 && "${TERM:-}" != "dumb" && "${OLC_NO_SPINNER:-0}" != "1" && "${OLC_UI_NO_ALT:-0}" != "1" ]]; then
    printf '\033[?1049h\033[H\033[2J'
    _OLC_UI_ALT=1
  fi
  _olc_ui_draw_header
}

_olc_ui_draw_header() {
  if declare -f tui_banner >/dev/null 2>&1; then
    tui_banner "$_OLC_UI_TITLE"          # 7 строк (пустая + рамка 3 + пустые 2 + reset)
    local line
    for line in ${_OLC_UI_INFO[@]+"${_OLC_UI_INFO[@]}"}; do
      tui_log_info "$line"
    done
    tui_divider
    # Точная высота шапки критична: от неё считаются scroll-регион (Ctrl+O)
    # и целевая строка финальной анимации схлопывания.
    _OLC_UI_HEADER_ROWS=$(( 7 + ${#_OLC_UI_INFO[@]} + 1 ))
  else
    echo "== $_OLC_UI_TITLE =="
    printf '%s\n' ${_OLC_UI_INFO[@]+"${_OLC_UI_INFO[@]}"}
    _OLC_UI_HEADER_ROWS=$(( 1 + ${#_OLC_UI_INFO[@]} ))
  fi
}

# Полная перерисовка КОМПАКТНОГО экрана (только alt-screen): очистка, шапка,
# хвост журнала шагов (transcript), влезающий по высоте терминала.
# Используется глобальным Ctrl+O (вкл — чистый старт подробного режима,
# выкл — скрыть ВСЕ подробные строки разом) и финалом при включённом verbose.
# Число занятых строк после перерисовки — в _OLC_UI_REDRAW_ROWS.
_OLC_UI_REDRAW_ROWS=0
_olc_ui_redraw_compact() {
  [[ "${_OLC_UI_ALT:-0}" == "1" ]] || return 1
  local term_h term_w
  term_h="$(_olc_ui_term_rows)"
  term_w="$(_olc_ui_term_cols)"
  # Сброс scroll-региона (мог остаться от verbose) + полная очистка экрана,
  # включая скроллбэк alt-screen (ESC[3J) — перерисовка стартует с чистого листа.
  _olc_progress_print '\033[r\033[2J\033[3J\033[H'
  # Шапка рисуется в ту же цель, что и бар (stdout или /dev/tty)
  if [[ -n "${_OLCRTC_PROGRESS_OUT:-}" ]]; then
    _olc_ui_draw_header > "$_OLCRTC_PROGRESS_OUT" 2>/dev/null || _olc_ui_draw_header
  else
    _olc_ui_draw_header
  fi
  local avail=$(( term_h - ${_OLC_UI_HEADER_ROWS:-0} - 2 ))
  (( avail < 0 )) && avail=0
  # Строки журнала обрезаются по ширине терминала: 1 строка = ровно 1 ряд.
  # Иначе длинные строки (пути логов и т.п.) заворачиваются, перерисовка
  # занимает больше рядов, экран прокручивается, шапка уезжает и подсчёт
  # _OLC_UI_REDRAW_ROWS съезжает (Баг A ловился на поздних шагах, где журнал
  # длинный и строки длинные).
  local maxw=$(( term_w - 5 ))
  (( maxw < 20 )) && maxw=20
  local shown=0 line
  local t="${_OLCRTC_PROGRESS_IPC_DIR:-}/transcript"
  if (( avail > 0 )) && [[ -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" && -s "$t" ]]; then
    while IFS= read -r line; do
      _olc_progress_print '  \033[2m→ %s\033[0m\n' "${line:0:maxw}"
      shown=$(( shown + 1 ))
    done < <(tail -n "$avail" "$t" 2>/dev/null)
  fi
  _OLC_UI_REDRAW_ROWS=$(( ${_OLC_UI_HEADER_ROWS:-0} + shown ))
  return 0
}

# Закрыть alt-screen (успешное завершение). После вызова печатать финальный
# вывод — он попадёт в основной буфер терминала.
olc_ui_end() {
  [[ "$_OLC_UI_ALT" == "1" ]] || return 0
  # \033[r — сброс scroll-региона (мог остаться от подробного режима Ctrl+O)
  printf '\033[r\033[?1049l'
  _OLC_UI_ALT=0
}

# Реальные размеры терминала. КРИТИЧНО: `tput lines/cols` внутри command
# substitution и/или фонового сабшелла спиннера (stdin=/dev/null, stdout=pipe)
# НЕ видит tty и молча отдаёт terminfo-дефолт 24/80 — из-за этого scroll-регион
# и перерисовка считались для «терминала 24x80» на любом реальном экране
# (Баг A: свёртка не очищала области ниже 24-й строки). stty size </dev/tty
# работает во всех этих контекстах.
_olc_ui_term_rows() {
  local sz=""
  sz="$(stty size </dev/tty 2>/dev/null)" || sz=""
  if [[ "$sz" =~ ^([0-9]+)[[:space:]]+[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  sz="$(tput lines 2>/dev/null)" || sz=""
  [[ "$sz" =~ ^[0-9]+$ ]] || sz=24
  printf '%s\n' "$sz"
}
_olc_ui_term_cols() {
  local sz=""
  sz="$(stty size </dev/tty 2>/dev/null)" || sz=""
  if [[ "$sz" =~ ^[0-9]+[[:space:]]+([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  sz="$(tput cols 2>/dev/null)" || sz=""
  [[ "$sz" =~ ^[0-9]+$ ]] || sz=80
  printf '%s\n' "$sz"
}

# Текущая строка курсора через DSR-запрос к терминалу (\033[6n).
# tty переводится в raw на время чтения ответа: в canonical-режиме (после
# восстановления настроек юзера) ответ терминала не доходит до read без
# newline и вдобавок эхается на экран мусором.
_olc_ui_cursor_row() {
  local esc="" row="" col="" fd saved=""
  { exec {fd}</dev/tty; } 2>/dev/null || return 1
  saved="$(stty -g </dev/tty 2>/dev/null)" || saved=""
  [[ -n "$saved" ]] && stty -icanon -echo min 0 time 0 </dev/tty 2>/dev/null || true
  printf '\033[6n' >/dev/tty 2>/dev/null || {
    [[ -n "$saved" ]] && stty "$saved" </dev/tty 2>/dev/null
    exec {fd}<&- 2>/dev/null
    return 1
  }
  IFS='[;' read -r -s -d R -t 0.4 esc row col <&"$fd" 2>/dev/null || row=""
  [[ -n "$saved" ]] && stty "$saved" </dev/tty 2>/dev/null
  exec {fd}<&- 2>/dev/null
  [[ "$row" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$row"
}

# Анимация финала: бар «поднимается» вверх, поглощая строки шагов,
# затем экран перерисовывается начисто (заголовок + бар 100%).
_olc_ui_collapse() {
  local bar_line="$1" msg_lines="${2:-0}" start_row="${3:-}"
  local term_h
  term_h="$(_olc_ui_term_rows)"
  # Защита: scroll-регион не должен быть активен во время анимации
  _olc_progress_print '\033[r'
  local target=$(( _OLC_UI_HEADER_ROWS + 1 ))
  (( target < 1 )) && target=1
  local row=""
  if [[ "$start_row" =~ ^[0-9]+$ ]]; then
    # Явная стартовая строка (после перерисовки экрана позиция известна точно)
    row="$start_row"
    (( row > term_h )) && row="$term_h"
  else
    row="$(_olc_ui_cursor_row 2>/dev/null)" || row=""
  fi
  if [[ -z "$row" ]]; then
    # Fallback: заголовок + напечатанные строки журнала + строка бара
    row=$(( _OLC_UI_HEADER_ROWS + msg_lines + 1 ))
    (( row > term_h )) && row="$term_h"
  fi
  local cur="$row"
  (( cur < target )) && cur="$target"
  local delay="${OLC_UI_COLLAPSE_DELAY:-0.03}"
  while :; do
    _olc_progress_print '\033[%d;1H\033[J%s' "$cur" "$bar_line"
    (( cur <= target )) && break
    cur=$(( cur - 1 ))
    sleep "$delay" 2>/dev/null || true
  done
  sleep "${OLC_UI_FINISH_HOLD:-1.0}" 2>/dev/null || true
  # Чистовая перерисовка: заголовок + закреплённый бар 100%
  _olc_progress_print '\033[2J\033[H'
  _olc_ui_draw_header
  _olc_progress_print '%s\n' "$bar_line"
  sleep "${OLC_UI_FINISH_HOLD2:-0.7}" 2>/dev/null || true
}

# После olc_ui_end: краткая сводка предупреждений из журнала шагов
# (чтобы ✗/WARN не потерялись вместе с alt-screen).
olc_ui_success_recap() {
  local t="${_OLCRTC_PROGRESS_IPC_DIR:-}/transcript"
  [[ -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" && -f "$t" ]] || return 0
  local warns
  warns="$(grep -E '✗|WARN|ошибка' "$t" 2>/dev/null || true)"
  [[ -n "$warns" ]] || return 0
  # «Сворачиваемость» сводки (T-4): показываются первые OLC_UI_RECAP_WARNS
  # строк (default 8), остальное схлопывается в счётчик «… и ещё N».
  local total shown
  total="$(wc -l <<<"$warns")"
  [[ "$total" =~ ^[0-9]+$ ]] || total=0
  shown="${OLC_UI_RECAP_WARNS:-8}"
  [[ "$shown" =~ ^[0-9]+$ ]] || shown=8
  echo ""
  if declare -f tui_log_warning >/dev/null 2>&1; then
    tui_log_warning "Во время обновления были предупреждения (не критично): $total"
  else
    echo "⚠ Предупреждения: $total"
  fi
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # Цветовая разметка (T-4): ошибки шагов — красным, WARN — жёлтым
    if [[ "$line" == *"✗"* || "$line" == *"ошибка"* || "$line" == *"ОШИБКА"* ]]; then
      printf '  %b→%b %b%s%b\n' "${TUI_RED:-}" "${TUI_RESET:-}" "${TUI_RED:-}" "$line" "${TUI_RESET:-}"
    else
      printf '  %b→%b %b%s%b\n' "${TUI_YELLOW:-}" "${TUI_RESET:-}" "${TUI_YELLOW:-}" "$line" "${TUI_RESET:-}"
    fi
  done <<<"$(head -n "$shown" <<<"$warns")"
  if (( total > shown )); then
    printf '  %b… и ещё %d предупрежд. — полный журнал в логах установки (ниже)%b\n' \
      "${TUI_DIM:-}" "$(( total - shown ))" "${TUI_RESET:-}"
  fi
}

# После olc_ui_end: пути ко ВСЕМ логам, использованным за сессию
# (копилка IPC/logpaths пополняется в _olc_progress_logfile).
olc_ui_logs_recap() {
  local lp="${_OLCRTC_PROGRESS_IPC_DIR:-}/logpaths"
  [[ -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" && -s "$lp" ]] || return 0
  echo ""
  if declare -f tui_log_info >/dev/null 2>&1; then
    tui_log_info "Логи установки:"
  else
    echo "Логи установки:"
  fi
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '  %b→ %s%b\n' "${TUI_DIM:-}" "$line" "${TUI_RESET:-}"
  done < "$lp"
}

# Аварийный выход из alt-screen: показать хвост журнала в основном терминале.
_olc_ui_abort_dump() {
  local rc="$1"
  [[ "$_OLC_UI_ALT" == "1" ]] || return 0
  # \033[r — сброс scroll-региона (мог остаться от подробного режима Ctrl+O)
  printf '\033[r\033[?1049l'
  _OLC_UI_ALT=0
  local t="${_OLCRTC_PROGRESS_IPC_DIR:-}/transcript"
  {
    echo ""
    printf '%b✗ %s прервано (rc=%s)%b\n' "${TUI_RED:-}" "${_OLC_UI_TITLE:-Обновление}" "$rc" "${TUI_RESET:-}"
    if [[ -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" && -s "$t" ]]; then
      printf '%bПоследние события:%b\n' "${TUI_DIM:-}" "${TUI_RESET:-}"
      tail -n 25 "$t" | sed 's/^/  → /'
    fi
    # При ошибке пути к логам особенно важны
    olc_ui_logs_recap
    echo "Продолжить с места остановки: sudo olc-update --resume"
  } >&2
}

# Финальный аккорд: остановить spinner и напечатать закреплённый бар 100%.
# В полноэкранной сессии — анимированное схлопывание строк шагов.
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
  local bar_line
  bar_line="$(printf '\033[32m✓\033[0m [%s] 100%% \033[2m(шаг %d/%d)\033[0m завершено' \
    "$bar" "$curr" "$total")"
  if [[ "$_OLC_UI_ALT" == "1" ]]; then
    local msg_lines=0
    if [[ -f "$_OLCRTC_PROGRESS_IPC_DIR/transcript" ]]; then
      msg_lines="$(wc -l < "$_OLCRTC_PROGRESS_IPC_DIR/transcript" 2>/dev/null)" || msg_lines=0
      [[ "$msg_lines" =~ ^[0-9]+$ ]] || msg_lines=0
    fi
    if [[ -f "$_OLCRTC_PROGRESS_IPC_DIR/verbose_used" || -f "$_OLCRTC_PROGRESS_IPC_DIR/verbose" ]]; then
      # Подробный режим включался ХОТЯ БЫ РАЗ за сессию (даже если к финалу
      # выключен): координаты курсора после verbose-стрима недостоверны —
      # сброс scroll-региона + чистая перерисовка компактного экрана, анимация
      # схлопывания стартует с ТОЧНО известной строки и гарантированно доезжает
      # до верхней панели, не оставляя обрывков verbose-строк (Баг B: раньше
      # этот путь включался только при активном verbose, а после тогл-off финал
      # уходил в ненадёжные DSR-гадания и анимация не проигрывалась).
      rm -f "$_OLCRTC_PROGRESS_IPC_DIR/verbose" \
        "$_OLCRTC_PROGRESS_IPC_DIR/verbose_used" 2>/dev/null || true
      _olc_progress_print '\033[r'
      if _olc_ui_redraw_compact; then
        _olc_ui_collapse "$bar_line" "$msg_lines" "$(( _OLC_UI_REDRAW_ROWS + 1 ))"
      else
        _olc_ui_collapse "$bar_line" "$msg_lines"
      fi
    else
      _olc_ui_collapse "$bar_line" "$msg_lines"
    fi
  else
    _olc_progress_print '%s\n' "$bar_line"
  fi
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
  # В alt-screen сессии при неактивном spinner строка печатается напрямую и
  # минует очередь → продублировать в transcript (для финальной сводки/дампа)
  if [[ "${_OLC_UI_ALT:-0}" == "1" && -n "${_OLCRTC_PROGRESS_IPC_DIR:-}" \
        && -d "${_OLCRTC_PROGRESS_IPC_DIR:-}" \
        && ! -f "${_OLCRTC_PROGRESS_IPC_DIR}/spinner" ]]; then
    printf '%s\n' "$*" >> "$_OLCRTC_PROGRESS_IPC_DIR/transcript" 2>/dev/null || true
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
  export -f _olc_progress_logfile 2>/dev/null || true
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
  # (в полноэкранной сессии — с анимацией схлопывания строк шагов)
  _olc_progress_finish
  if command -v jq >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    jq --arg t "$(date -u +%FT%TZ)" '.finished=$t | .failed=null' \
      "$OLCRTC_STATE_FILE" > "$tmp" && mv "$tmp" "$OLCRTC_STATE_FILE"
  fi
  # В alt-screen сессии служебная строка не нужна — финал печатает вызывающий код
  [[ "${_OLC_UI_ALT:-0}" == "1" ]] && return 0
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
