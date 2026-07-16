#!/usr/bin/env bash
# Регрессия TUI: Ctrl+O (подробный вывод) на ДЛИННОМ прогоне под pty.
# Проверяет фиксы Багов A/B (263bfc6 → follow-up):
#   1. scroll-регион ставится по РЕАЛЬНОЙ высоте терминала (не terminfo-дефолт 24);
#   2. Ctrl+O-off на позднем шаге → чистая перерисовка компактного экрана,
#      verbose-строки больше не стримятся;
#   3. финальная анимация схлопывания проигрывается ДЕТЕРМИНИРОВАННО после
#      verbose-сессии (даже если к финалу verbose выключен) — без DSR-гаданий;
#   4. сводка «Логи установки:» печатается в финале.
# Требует python3 (stdlib: pty/select). Без TTY-эмуляции тест невозможен —
# при отсутствии python3 аккуратно скипается.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[tui-verbose-test] SKIP: python3 не найден"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/olcrtc-tui-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- синтетический длинный прогон (11 шагов, много verbose-строк) ---
cat > "$WORK/fake-install.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="${OLC_SCRIPTS_DIR:?}"
WORK="${TUIREPRO_WORK:?}"
export OLCRTC_STATE_DIR="$WORK/state"
export OLCRTC_STATE_FILE="$OLCRTC_STATE_DIR/install-state.json"
export OLC_LANG=ru
export OLC_UI_FINISH_HOLD=0.3 OLC_UI_FINISH_HOLD2=0.2 OLC_UI_COLLAPSE_DELAY=0.02
source "$SCRIPT_DIR/lib-tui.sh"
source "$SCRIPT_DIR/lib-install-state.sh"
export OLCRTC_TOTAL_STEPS=11
LOGDIR="$WORK/logs"; mkdir -p "$LOGDIR"
fake_step() {
  local n="$1" lines="$2"
  local log="$LOGDIR/step${n}.log"
  : > "$log"
  _olc_progress_logfile "$log"
  olc_progress_msg "шаг ${n}: запущено · детали: ${log} (длинная строка журнала как в реальном olc-update, с путями логов и пояснениями)"
  local i
  for ((i=1; i<=lines; i++)); do
    printf '[step%d] verbose line %d: build output, довольно длинная строка вывода которая может заворачиваться по ширине терминала\n' "$n" "$i" >> "$log"
    (( i % 10 == 0 )) && sleep 0.12
  done
  olc_progress_msg "✓ шаг ${n} — готово · детали: ${log}"
  # синтетическое предупреждение для проверки цветной сводки финала
  if [[ "$n" == "6" ]]; then
    olc_progress_msg "✗ тестовый sync — ошибка rc=2 (синтетика) → WARN"
  fi
  _olc_progress_logfile ""
}
olc_ui_begin "Обновление Olc-cost-l" \
  "Режим: UPDATE — тестовый прогон" \
  "Профиль: test (tor=1 split=1 zapret=1)" \
  "Прервалось? Продолжить: sudo olc-update --resume"
state_init --fresh
state_step patches               fake_step 1 60
state_step sysctl                fake_step 2 10
state_step warp                  fake_step 3 5
state_step tor                   fake_step 4 90
state_step split                 fake_step 5 90
state_step fetch-community-lists fake_step 6 30
state_step zapret                fake_step 7 200
state_step systemd               fake_step 8 150
state_step cron                  fake_step 9 80
state_step cleanup-tmp           fake_step 10 80
state_step restart-manager       fake_step 11 40
state_finish
olc_ui_end
tui_log_success "Обновление успешно завершено!"
olc_ui_success_recap
olc_ui_logs_recap
FAKE

OLC_SCRIPTS_DIR="$SCRIPT_DIR" TUIREPRO_WORK="$WORK" FAKE_INSTALL="$WORK/fake-install.sh" \
python3 - <<'PY'
import os, pty, time, select, re, fcntl, termios, struct, sys

ROWS, COLS = 40, 100
DSR = b"\x1b[6n"
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp("bash", ["bash", os.environ["FAKE_INSTALL"]])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

raw = b""
def pump(t=0.05):
    global raw
    r, _, _ = select.select([fd], [], [], t)
    if not r: return False
    try: d = os.read(fd, 65536)
    except OSError: return False
    if not d: return False
    raw += d
    if DSR in d:
        # эмуляция ответа терминала на DSR (позиция не важна для ассертов)
        try: os.write(fd, b"\x1b[40;1R")
        except OSError: pass
    return True

def wait_for(p, dl=180):
    t0 = time.time(); rx = re.compile(p.encode())
    while time.time() - t0 < dl:
        pump()
        if rx.search(raw): return True
    return False

def pump_for(sec):
    t0 = time.time()
    while time.time() - t0 < sec: pump()

def alive():
    try: return os.waitpid(pid, os.WNOHANG) == (0, 0)
    except ChildProcessError: return False

fails = []
def check(name, ok):
    print(("  ✓ " if ok else "  ✗ ") + name)
    if not ok: fails.append(name)

# 1) дождаться позднего шага (7/11) с длинным журналом
assert wait_for(r"7/11"), "не дождались шага 7/11"
pump_for(0.3)
os.write(fd, b"\x0f")          # Ctrl+O ON
pump_for(2.5)                  # стримятся verbose-строки
mark_off = len(raw)
os.write(fd, b"\x0f")          # Ctrl+O OFF на позднем шаге
pump_for(1.2)
mark_after = len(raw)

t0 = time.time()
while alive() and time.time() - t0 < 300: pump(0.1)
pump_for(1.0)

s = raw.decode("utf-8", "replace")
def c(b): return len(raw[:b].decode("utf-8", "replace"))

# --- ассерты ---
regions = re.findall(r"\x1b\[(\d+);(\d+)r", s)
check("scroll-регион по реальной высоте pty (низ=40, не 24)",
      bool(regions) and all(bot == "40" for _, bot in regions))

check("verbose включился (сепаратор + лог-заголовок)",
      "── подробный вывод (Ctrl+O — скрыть)" in s and "── лог:" in s)

after_off = s[c(mark_off):]
check("Ctrl+O-off → полная перерисовка компактного экрана ([r + 2J)",
      re.search(r"\x1b\[r\x1b\[2J", after_off) is not None)

redraw_m = re.search(r"\x1b\[r\x1b\[2J", after_off)
post_redraw = after_off[redraw_m.end():] if redraw_m else ""
# после off-перерисовки dim-строки «· verbose line» не должны стримиться
check("после off-тоггла verbose-строки не стримятся",
      "· [step" not in post_redraw and "verbose line" not in
      re.sub(r"\x1b\[2m→ [^\n]*", "", post_redraw))

frames = [int(m.group(1)) for m in re.finditer(r"\x1b\[(\d+);1H\x1b\[J", after_off)]
mono = sum(1 for a, b in zip(frames, frames[1:]) if b == a - 1)
check("финальная анимация схлопывания проигрывается (>=5 убывающих кадров)",
      len(frames) >= 5 and mono >= len(frames) - 2)

check("сводка «Логи установки:» в финале", "Логи установки:" in s)
check("alt-screen закрыт корректно", "\x1b[?1049l" in s)

# индикатор ^O живёт в строке бара и меняет текст по состоянию verbose
check("индикатор [^O детали] в строке бара", "[^O детали]" in s)
check("индикатор [^O скрыть детали] при включённом verbose",
      "[^O скрыть детали]" in s)

# строка бара не заворачивается: видимая длина каждого кадра <= ширины pty
ansi = re.compile(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\[\?[0-9]+[hl]")
too_wide = []
for m in re.finditer(r"\r\x1b\[K\x1b\[36m[^\r\n]*", s):
    vis = ansi.sub("", m.group(0)[3:])
    if len(vis) > COLS:
        too_wide.append(len(vis))
check("строка бара не шире терминала (обрезка по ширине)", not too_wide)

# цветная сводка предупреждений финала (после alt-screen)
check("цветная сводка предупреждений в финале",
      "Во время обновления были предупреждения (не критично):" in s
      and "тестовый sync — ошибка rc=2" in s)

if fails:
    print("[tui-verbose-test] FAIL: " + "; ".join(fails))
    sys.exit(1)
PY

printf '[tui-verbose-test] OK: регион по высоте tty, off-тоггл, финальная анимация, recap\n'
