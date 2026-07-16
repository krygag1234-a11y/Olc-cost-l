#!/usr/bin/env bash
# Регрессия TUI: интерактивное меню tui_menu под pty.
# Исторический баг: все вызовы — mode=$(tui_menu ...), а меню рисовалось в
# stdout → целиком съедалось command substitution (юзер НИЧЕГО не видел),
# а `read -t 1` через секунду молча возвращал дефолт (пункт 0). Итог:
# «интерактивный выбор при обновлении не показывается», всегда тихая
# «Доустановка». Тест проверяет:
#   1. меню РЕАЛЬНО видно на терминале (рисуется в /dev/tty, не в stdout);
#   2. таймаут read НЕ завершает меню молча (ждёт выбора дольше 1с);
#   3. выбор цифрой N возвращает индекс N-1 в stdout;
#   4. выбор стрелкой ↓ + Enter возвращает индекс 1;
#   5. в захваченном $(…) — ТОЛЬКО индекс, без ANSI/текста меню;
#   6. без терминала (setsid, нет /dev/tty) — немедленный дефолт «0».
# Требует python3 (stdlib: pty/select); без него скипается.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[tui-menu-test] SKIP: python3 не найден"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/olcrtc-menu-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/fake-menu.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
source "${OLC_SCRIPTS_DIR:?}/lib-tui.sh"
echo "BEFORE-MENU"
mode=$(tui_menu "Выберите режим обновления:" \
  "Доустановка (быстро - skip работающих компонентов)" \
  "Обновление (полная пересборка - patches, binaries)" \
  "Отмена")
echo "RESULT=[$mode]"
FAKE

# --- 6) без терминала: setsid отрывает контролирующий tty → дефолт 0 сразу ---
no_tty_out="$(OLC_SCRIPTS_DIR="$SCRIPT_DIR" setsid -w bash "$WORK/fake-menu.sh" </dev/null 2>/dev/null || true)"
if [[ "$no_tty_out" == *"RESULT=[0]"* ]]; then
  echo "  ✓ без /dev/tty — немедленный дефолт 0"
else
  echo "  ✗ без /dev/tty — немедленный дефолт 0 (got: $no_tty_out)"
  exit 1
fi

OLC_SCRIPTS_DIR="$SCRIPT_DIR" FAKE_MENU="$WORK/fake-menu.sh" python3 - <<'PY'
import os, pty, time, select, re, fcntl, termios, struct, sys

ROWS, COLS = 40, 100
fails = []
def check(name, ok):
    print(("  ✓ " if ok else "  ✗ ") + name)
    if not ok: fails.append(name)

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

def run_case(keys_fn):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execvp("bash", ["bash", os.environ["FAKE_MENU"]])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    raw = b""
    def pump(t=0.05):
        nonlocal raw
        r, _, _ = select.select([fd], [], [], t)
        if not r: return False
        try: d = os.read(fd, 65536)
        except OSError: return False
        if not d: return False
        raw += d
        return True
    def wait_for(p, dl=20):
        t0 = time.time(); rx = re.compile(p.encode())
        while time.time() - t0 < dl:
            pump()
            if rx.search(raw): return True
        return False
    def pump_for(sec):
        t0 = time.time()
        while time.time() - t0 < sec: pump()
    keys_fn(fd, wait_for, pump_for, lambda: raw)
    # дождаться завершения
    t0 = time.time()
    while time.time() - t0 < 15:
        pump(0.1)
        try:
            if os.waitpid(pid, os.WNOHANG) != (0, 0): break
        except ChildProcessError:
            break
    pump_for(0.3)
    try: os.close(fd)
    except OSError: pass
    return raw.decode("utf-8", "replace")

# --- кейс 1: меню видно; >1.5с без ввода НЕ выходит; цифра 3 → индекс 2 ---
def case1(fd, wait_for, pump_for, get_raw):
    assert wait_for(r"Выберите режим обновления:"), "меню не отрисовалось"
    pump_for(1.6)  # старый баг: через 1с read-таймаут молча возвращал дефолт
    s = get_raw().decode("utf-8", "replace")
    check("таймаут read не завершает меню молча (нет RESULT через 1.6с)",
          "RESULT=[" not in s)
    os.write(fd, b"3")

s1 = run_case(case1)
check("меню видно на терминале (заголовок и пункты в /dev/tty)",
      "Выберите режим обновления:" in s1 and "Доустановка" in s1
      and "Enter — подтвердить" in s1)
check("цифра 3 → RESULT=[2]", "RESULT=[2]" in s1)
m = re.search(r"RESULT=\[([^\]]*)\]", s1)
check("в $(…) попал только индекс (без ANSI/текста меню)",
      bool(m) and m.group(1).strip() == "2")

# --- кейс 2: стрелка вниз + Enter → индекс 1 ---
def case2(fd, wait_for, pump_for, get_raw):
    assert wait_for(r"Выберите режим обновления:"), "меню не отрисовалось"
    pump_for(0.3)
    os.write(fd, b"\x1b[B")   # стрелка вниз
    pump_for(0.4)
    os.write(fd, b"\r")       # Enter

s2 = run_case(case2)
check("↓ + Enter → RESULT=[1]", "RESULT=[1]" in s2)

# --- кейс 3: Enter сразу → дефолт 0 ---
def case3(fd, wait_for, pump_for, get_raw):
    assert wait_for(r"Выберите режим обновления:"), "меню не отрисовалось"
    pump_for(0.3)
    os.write(fd, b"\r")

s3 = run_case(case3)
check("Enter сразу → RESULT=[0]", "RESULT=[0]" in s3)

if fails:
    print("[tui-menu-test] FAIL: " + "; ".join(fails))
    sys.exit(1)
PY

printf '[tui-menu-test] OK: меню видно, таймаут не роняет, цифры/стрелки/Enter, чистый stdout\n'
