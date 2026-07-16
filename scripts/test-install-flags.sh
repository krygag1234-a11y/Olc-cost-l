#!/usr/bin/env bash
# Регрессия: проверка, что ВСЕ существующие и подходящие флаги установки и
# обновления корректно парсятся и НЕ ломают скрипты при явном указании.
#
# Использует dry-run режим `--plan`:
#   - install.sh --plan  → парсит флаги, печатает [install-plan]/[plan], НЕ ставит
#   - olc-update.sh --plan → парсит флаги, печатает [update-plan], НЕ обновляет
#   - agent-bootstrap.sh --plan → печатает [plan], НЕ трогает хост
#
# Проверяем:
#   1. корректные комбинации → rc=0 и ожидаемый режим/компоненты;
#   2. конфликтующие флаги (--tor+--warp, --split без --tor, --bridges без --tor)
#      → tui_fatal (rc!=0);
#   3. неизвестные флаги в неинтерактивной среде → не падают в парсинге до плана.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOT="$SCRIPT_DIR/agent-bootstrap.sh"
UPD="$SCRIPT_DIR/olc-update.sh"

fails=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; fails=$((fails + 1)); }

# run_boot <expected-substring-in-plan> <args...>
run_boot() {
  local want="$1"; shift
  local out rc
  out="$(OLC_REPO_ROOT="$REPO_ROOT" bash "$BOOT" "$@" --plan 2>&1)"; rc=$?
  if [[ $rc -eq 0 && "$out" == *"$want"* ]]; then
    pass "bootstrap [$*] → $want"
  else
    fail "bootstrap [$*] (rc=$rc) ожидали '$want', получили: $(echo "$out" | tail -1)"
  fi
}

# expect_conflict <args...> — ожидаем НЕнулевой rc (tui_fatal)
expect_conflict() {
  local out rc
  out="$(OLC_REPO_ROOT="$REPO_ROOT" bash "$BOOT" "$@" --plan 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    pass "bootstrap [$*] → отклонено (rc=$rc)"
  else
    fail "bootstrap [$*] должно было упасть, но rc=0: $(echo "$out" | tail -1)"
  fi
}

# run_upd <expected-substring> <args...>
run_upd() {
  local want="$1"; shift
  local out rc
  out="$(bash "$UPD" "$@" --plan 2>&1)"; rc=$?
  if [[ $rc -eq 0 && "$out" == *"$want"* ]]; then
    pass "olc-update [$*] → $want"
  else
    fail "olc-update [$*] (rc=$rc) ожидали '$want', получили: $(echo "$out" | tail -1)"
  fi
}

echo "== agent-bootstrap: корректные комбинации флагов установки =="
run_boot "full=1"                                    --full
run_boot "tor=1"                                     --with-tor
run_boot "tor=1"                                     --tor
run_boot "zapret=1"                                  --zapret
run_boot "bridges=1"                                 --bridges
run_boot "warp=1"                                    --with-warp
run_boot "warp=1"                                    --warp
run_boot "tor=0"                                     --no-tor
run_boot "split=0"                                   --full --no-split
run_boot "zapret=0"                                  --full --no-zapret
run_boot "bridges=0"                                 --full --no-bridges
run_boot "access=ssh"                                --full --ssh
run_boot "access=ip"                                 --full --ip
run_boot "update=1"                                  --update
run_boot "incremental=1"                             --incremental
run_boot "full=1"                                    --full --manager-stable
run_boot "full=1"                                    --full --manager-latest
run_boot "full=1"                                    --full --force-sha-update
run_boot "ru=1"                                      --ru
run_boot "tor=0"                                     --foreign

# ПРИМЕЧАНИЕ: конфликт вычисляется по СОСТОЯНИЮ после парсинга всех флагов, а
# флаги применяются по порядку. Поэтому «--tor --warp» НЕ конфликт (warp
# сбрасывает tor=0 последним), а «--warp --tor» — конфликт (оба =1).
# Аналогично split/bridges с дефолтным tor=1 валидны; конфликт — только когда
# tor явно выключен ПОСЛЕ включения компонента, зависящего от него.
echo "== agent-bootstrap: конфликтующие флаги отклоняются =="
expect_conflict --warp --tor          # оба включены → tor+warp конфликт
expect_conflict --full --no-tor --split   # split при tor=0
expect_conflict --no-tor --bridges        # bridges после выключения tor... (bridges ставит RU но не tor)
expect_conflict --full --no-tor --bridges # bridges при tor=0

echo "== agent-bootstrap: валидные (порядок сбрасывает зависимость) =="
run_boot "warp=1"  --tor --warp       # --warp последний → tor=0, конфликта нет
run_boot "split=1" --split            # split с дефолтным tor=1 — ок

echo "== install.sh: dry-run плана с флагами (без сети/сборки) =="
inst() {
  local want="$1"; shift
  local out rc
  out="$(OLC_INSTALL_DIR="$REPO_ROOT" bash "$REPO_ROOT/install.sh" "$@" --plan 2>&1)"; rc=$?
  if [[ $rc -eq 0 && "$out" == *"$want"* ]]; then
    pass "install.sh [$*] → $want"
  else
    fail "install.sh [$*] (rc=$rc) ожидали '$want', получили: $(echo "$out" | grep -E 'plan' | tail -1)"
  fi
}
# install.sh требует root для полного прогона, но --plan выходит до сети;
# запускаем только если root (иначе скип, чтобы тест не был флаки).
if [[ "$(id -u)" -eq 0 ]]; then
  inst "[install-plan]"        --full
  inst "tor=0"                 --no-tor
  inst "warp=1"                --with-warp
  inst "access=ssh"            --full --ssh
  inst "zapret=0"              --full --no-zapret
else
  echo "  (skip install.sh --plan: нужен root; проверено в bootstrap-плане выше)"
fi

echo "== olc-update: все флаги обновления =="
run_upd "mode=<menu/default>"               # без флагов → меню
run_upd "mode=--update"                       --update
run_upd "mode=--incremental"                  --incremental
run_upd "mode=--update(default-with-flags)"   --manager-latest
run_upd "mode=--update(default-with-flags)"   --manager-stable
run_upd "mode=--update(default-with-flags)"   --ssh
run_upd "mode=--update(default-with-flags)"   --force-sha-update
run_upd "unknown=[--lolwut]"                  --lolwut
run_upd "mode=--update"                       --update --manager-stable --ssh --force-sha-update

echo ""
if [[ "$fails" -eq 0 ]]; then
  echo "[install-flags-test] OK: все флаги установки и обновления парсятся без поломок"
else
  echo "[install-flags-test] FAIL: $fails проверок не прошли"
  exit 1
fi

# ── PTY: добор режима доступа при --full без --ssh/--ip ──────────────────────
# Флаг покрывает только свой выбор: --full задаёт компоненты, но НЕ доступ →
# должно всплыть меню IP/SSH; с --full --ip меню НЕ должно появляться.
if command -v python3 >/dev/null 2>&1; then
  echo "== PTY: добор недостающего выбора (IP/SSH) при --full =="
  OLC_INSTALL_DIR="$REPO_ROOT" python3 - "$REPO_ROOT" <<'PY'
import os, pty, select, time, re, sys, fcntl, termios, struct
repo = sys.argv[1]
fails = []
def check(n, ok):
    print(("  ✓ " if ok else "  ✗ ") + n)
    if not ok: fails.append(n)

def run(args, keys=None, wait=None):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ["OLC_INSTALL_DIR"] = repo
        os.environ["OLC_ASSUME_FRESH"] = "1"       # считать систему чистой → MODE=full
        os.environ["OLC_EXIT_AFTER_PROMPT"] = "1"  # выйти сразу после добора
        os.execvp("bash", ["bash", repo + "/install.sh"] + args)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))
    raw = b""; sent = False; t0 = time.time()
    while time.time() - t0 < 25:
        r,_,_ = select.select([fd], [], [], 0.2)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            raw += d
        if keys and not sent and wait and re.search(wait.encode(), raw):
            time.sleep(0.4); os.write(fd, keys); sent = True
        try:
            if os.waitpid(pid, os.WNOHANG) != (0,0): break
        except ChildProcessError: break
    for _ in range(5):
        r,_,_ = select.select([fd],[],[],0.2)
        if r:
            try: raw += os.read(fd,65536)
            except OSError: break
    return raw.decode("utf-8","replace")

# 1) --full без доступа → меню IP/SSH появляется; выбираем цифру 2 (SSH)
s1 = run(["--full"], keys=b"2", wait=r"Режим доступа к панели")
check("--full → меню IP/SSH показано", "Режим доступа к панели" in s1)
check("--full + выбор SSH → boot_args содержит --ssh",
      "--ssh" in s1 and "access_set=1" in s1)

# 2) --full --ip → меню НЕ показывается, доступ уже задан
s2 = run(["--full", "--ip"])
check("--full --ip → меню доступа НЕ показано", "Режим доступа к панели" not in s2)
check("--full --ip → access_set=1 без меню", "access_set=1" in s2 and "--ip" in s2)

if fails:
    print("[install-flags-test] PTY FAIL: " + "; ".join(fails)); sys.exit(1)
print("[install-flags-test] OK: добор IP/SSH работает (флаг пропускает только свой выбор)")
PY
  rc=$?
  [[ $rc -ne 0 ]] && exit 1
else
  echo "  (skip PTY-тест добора: нет python3)"
fi
exit 0
