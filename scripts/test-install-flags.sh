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
expect_update_rejected() {
  local out rc
  out="$(bash "$UPD" "$@" --plan 2>&1)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"manager"* ]]; then
    pass "olc-update [$*] -> obsolete manager mode rejected"
  else
    fail "olc-update [$*] must reject obsolete manager mode (rc=$rc)"
  fi
}

expect_install_rejected() {
  local out rc
  out="$(OLC_INSTALL_DIR="$REPO_ROOT" bash "$REPO_ROOT/install.sh" "$@" --plan 2>&1)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"Manager"* ]]; then
    pass "install.sh [$*] -> obsolete manager mode rejected"
  else
    fail "install.sh [$*] must reject obsolete manager mode (rc=$rc)"
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

echo "== contract: полная таблица режимов установки =="
run_matrix() {
  local want="$1"; shift
  local out rc
  out="$(OLC_REPO_ROOT="$REPO_ROOT" bash "$BOOT" "$@" --plan 2>&1)"; rc=$?
  if [[ $rc -eq 0 && "$out" == *"$want"* ]]; then
    pass "matrix [$*] → $want"
  else
    fail "matrix [$*] (rc=$rc) expected '$want', got: $(echo "$out" | tail -1)"
  fi
}
run_matrix "tor=1 split=1 zapret=1 bridges=1 warp=0" --full
run_matrix "tor=0 split=0 zapret=1 bridges=0 warp=0" --full --no-tor
run_matrix "tor=1 split=1 zapret=1 bridges=0 warp=0" --full --no-bridges
run_matrix "tor=1 split=0 zapret=1 bridges=1 warp=0" --full --no-split
run_matrix "tor=1 split=1 zapret=0 bridges=1 warp=0" --full --no-zapret
run_matrix "tor=1 split=0 zapret=0 bridges=0 warp=0" --tor
run_matrix "tor=1 split=0 zapret=0 bridges=1 warp=0" --tor --bridges
run_matrix "tor=1 split=1 zapret=0 bridges=0 warp=0" --tor --split
run_matrix "tor=0 split=0 zapret=0 bridges=1 warp=0 requires_existing_tor=1" --bridges
run_matrix "tor=0 split=1 zapret=0 bridges=0 warp=0 requires_existing_tor=1" --split
run_matrix "tor=0 split=0 zapret=1 bridges=0 warp=0" --zapret
run_matrix "tor=0 split=0 zapret=0 bridges=0 warp=1" --warp
run_matrix "tor=1 split=1 zapret=1 bridges=1 warp=0" --tor --bridges --split --zapret

echo "== agent-bootstrap: корректные комбинации флагов установки =="
run_boot "full=1"                                    --full
run_boot "tls=1 tls_mode=selfsigned"                   --full
run_boot "tls=0 tls_mode=http"                         --full --http
run_boot "tls=0 tls_mode=http"                         --http --full
run_boot "tls=1 tls_mode=letsencrypt"                  --full --https-letsencrypt
run_boot "tls=1 tls_mode=selfsigned"                   --full --https-self-signed
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
expect_conflict --full --manager-stable
expect_conflict --full --manager-latest
run_boot "full=1"                                    --full --force-sha-update
run_boot "ru=1"                                      --ru
run_boot "tor=0"                                     --foreign

# ПРИМЕЧАНИЕ: конфликт вычисляется по СОСТОЯНИЮ после парсинга всех флагов, а
# флаги применяются по порядку. Поэтому «--tor --warp» НЕ конфликт (warp
# сбрасывает tor=0 последним), а «--warp --tor» — конфликт (оба =1).
# Аналогично split/bridges с дефолтным tor=1 валидны; конфликт — только когда
# tor явно выключен ПОСЛЕ включения компонента, зависящего от него.
echo "== agent-bootstrap: конфликтующие флаги отклоняются =="
expect_conflict --warp --tor
expect_conflict --full --no-tor --split   # split при tor=0
expect_conflict --no-tor --bridges        # bridges после выключения tor... (bridges ставит RU но не tor)
expect_conflict --full --no-tor --bridges # bridges при tor=0

echo "== agent-bootstrap: зависимости от уже установленного Tor =="
expect_conflict --tor --warp
run_boot "requires_existing_tor=1" --split
run_boot "requires_existing_tor=1" --bridges

echo "== install.sh: dry-run плана с флагами (без сети/сборки) =="
expect_install_rejected --manager-stable
expect_install_rejected --manager-latest
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
  inst "--https-self-signed"    --full
  inst "--https-letsencrypt"    --full --https-letsencrypt
  inst "--http"                 --full --http
  inst "tor=0"                 --no-tor
  inst "warp=1"                --with-warp
  inst "access=ssh"            --full --ssh
  inst "zapret=0"              --full --no-zapret
  inst "tor=1 split=0 zapret=0 bridges=0 warp=0" --tor
  inst "tor=0 split=0 zapret=1 bridges=0 warp=0" --zapret
else
  echo "  (skip install.sh --plan: нужен root; проверено в bootstrap-плане выше)"
fi

echo "== olc-update: все флаги обновления =="
run_upd "mode=<menu/default>"               # без флагов → меню
run_upd "mode=--update"                       --update
run_upd "mode=--incremental"                  --incremental
expect_update_rejected --manager-latest
expect_update_rejected --manager-stable
run_upd "mode=--update(default-with-flags)"   --ssh
run_upd "mode=--update(default-with-flags)"   --https-letsencrypt
run_upd "mode=--update(default-with-flags)"   --https-self-signed
run_upd "mode=--update(default-with-flags)"   --http
run_upd "mode=--update(default-with-flags)"   --force-sha-update
run_upd "unknown=[--lolwut]"                  --lolwut
expect_update_rejected --update --manager-stable --ssh --force-sha-update

echo "== finish help: URL соответствует сохранённому TLS-режиму =="
finish_help() {
  local access="$1" tls_mode="$2"
  PANEL_ACCESS="$access" PANEL_TLS_MODE="$tls_mode" REPO_ROOT="$REPO_ROOT" bash -c '
    source "$1/scripts/lib-olc-ru.sh"
    olc_detect_panel_host() { echo 203.0.113.10; }
    olc_print_finish_help 8888
  ' _ "$REPO_ROOT" 2>&1
}
out="$(finish_help ip letsencrypt)"
if [[ "$out" == *"https://203.0.113.10:8888/admin"* && "$out" == *"https://127.0.0.1:8888/admin"* ]]; then
  pass "finish help: Let's Encrypt → HTTPS"
else
  fail "finish help: Let's Encrypt не напечатал HTTPS URL"
fi
out="$(finish_help ssh http)"
if [[ "$out" == *"http://127.0.0.1:8888/admin"* && "$out" != *"https://127.0.0.1:8888/admin"* ]]; then
  pass "finish help: SSH + HTTP → HTTP"
else
  fail "finish help: SSH + HTTP напечатал неверную схему"
fi

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
s1 = run(["--full"], keys=b"3", wait=r"Режим доступа к панели")
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

echo "== install.sh: fresh curl-style menu bootstraps its own TUI libraries =="
REG_WORK="$(mktemp -d "${TMPDIR:-/tmp}/olc-install-regression.XXXXXX")"
trap 'rm -rf "$REG_WORK"' EXIT
SEED="$REG_WORK/seed"
FRESH="$REG_WORK/fresh-install"
FRESH_FULL="$REG_WORK/fresh-full-install"
INSTALLED="$REG_WORK/installed"
DIRTY="$REG_WORK/dirty-install"
mkdir -p "$SEED"
git -C "$REPO_ROOT" archive HEAD | tar -x -C "$SEED"
# Include the working-tree install.sh so this regression runs before commit too.
cp "$REPO_ROOT/install.sh" "$SEED/install.sh"
cp "$REPO_ROOT/scripts/lib-olc-core.sh" "$SEED/scripts/lib-olc-core.sh"
git -C "$SEED" init -q -b main
git -C "$SEED" config user.email test@example.invalid
git -C "$SEED" config user.name olc-test
git -C "$SEED" add .
git -C "$SEED" commit -qm seed
git clone -q "file://$SEED" "$INSTALLED"

if command -v python3 >/dev/null 2>&1; then
  OLC_TEST_SEED="$SEED" OLC_TEST_FRESH="$FRESH" OLC_TEST_FRESH_FULL="$FRESH_FULL" \
    OLC_TEST_INSTALLED="$INSTALLED" OLC_TEST_INSTALL="$REPO_ROOT/install.sh" python3 - <<'PY'
import os, pty, select, time, fcntl, termios, struct

def run_case(name, target, args, prompts, extra_env, assertions):
    pid, fd = pty.fork()
    if pid == 0:
        env = {
            "TERM": "xterm-256color",
            "OLC_INSTALL_DIR": target,
            "OLC_REPO_URL": "file://" + os.environ["OLC_TEST_SEED"],
            "OLC_REPO_BRANCH": "main",
            "OLC_INSTALL_PROFILE_PATH": target + ".profile.json",
        }
        env.update(extra_env)
        os.environ.update(env)
        os.execvp("bash", ["bash", os.environ["OLC_TEST_INSTALL"], *args])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 110, 0, 0))
    raw = b""; prompt_index = 0; started = time.time()
    while time.time() - started < 50:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try: data = os.read(fd, 65536)
            except OSError: break
            if not data: break
            raw += data
        if prompt_index < len(prompts) and prompts[prompt_index][0].encode() in raw:
            os.write(fd, prompts[prompt_index][1].encode())
            prompt_index += 1
        try:
            if os.waitpid(pid, os.WNOHANG) != (0, 0): break
        except ChildProcessError:
            break
    text = raw.decode("utf-8", "replace")
    checks = assertions(text)
    bad = [label for label, ok in checks.items() if not ok]
    for label, ok in checks.items(): print(("  ✓ " if ok else "  ✗ ") + name + ": " + label)
    if prompt_index != len(prompts): bad.append("not all prompts answered")
    if bad:
        print(text[-3500:])
        raise SystemExit(name + " failed: " + ", ".join(bad))

fresh = os.environ["OLC_TEST_FRESH"]
run_case(
    "fresh selective", fresh, [],
    [("Режим доступа к панели:", "3"), ("Компоненты для установки:", "4"),
     ("Установить Tor?", "1"), ("Установить мосты Tor?", "2"),
     ("Установить Split-routing?", "1"), ("Установить Zapret", "2")],
    {"OLC_ASSUME_FRESH": "1", "OLC_EXIT_AFTER_PROMPT": "1"},
    lambda text: {
        "clone created": os.path.isdir(os.path.join(fresh, ".git")),
        "shared component TUI shown": "Интерактивная установка Olc-cost-l" in text and "Компоненты для установки:" in text,
        "selective flags preserved": "[install-postprompt]" in text and "--ssh" in text and "--no-bridges" in text and "--no-zapret" in text and "--no-tor" not in text and "--no-split" not in text,
        "profile kept outside live state": os.path.isfile(fresh + ".profile.json"),
    })

fresh_full = os.environ["OLC_TEST_FRESH_FULL"]
run_case(
    "fresh --full", fresh_full, ["--full"], [("Режим доступа к панели", "3")],
    {"OLC_ASSUME_FRESH": "1", "OLC_EXIT_AFTER_PROMPT": "1"},
    lambda text: {
        "early clone provides access TUI": os.path.isdir(os.path.join(fresh_full, ".git")) and "Режим доступа к панели" in text,
        "component menu correctly skipped": "Компоненты для установки:" not in text,
        "access selection reaches args": "[install-postprompt]" in text and "--ssh" in text,
    })

installed = os.environ["OLC_TEST_INSTALLED"]
run_case(
    "installed curl entry", installed, [], [("Olc-cost-l уже установлен", "2")],
    {"OLC_ASSUME_INSTALLED": "1", "OLC_EXIT_AFTER_MODE_SELECTION": "1"},
    lambda text: {
        "action menu shown": "Olc-cost-l уже установлен" in text,
        "update choice routed to update": "[install-mode] state=installed mode=update" in text,
        "fresh component menu not shown": "Компоненты для установки:" not in text,
    })
PY
  fresh_pty_rc=$?
  if [[ "$fresh_pty_rc" -ne 0 ]]; then
    exit "$fresh_pty_rc"
  fi
else
  echo "  (skip fresh curl-style PTY: нет python3)"
fi

echo "== install.sh: dirty installed repository is never reset =="
git clone -q "file://$SEED" "$DIRTY"
printf '\nlocal-user-change\n' >> "$DIRTY/README.md"
DIRTY_BEFORE="$(sha256sum "$DIRTY/README.md" | awk '{print $1}')"
dirty_out="$(OLC_INSTALL_DIR="$DIRTY" OLC_REPO_URL="file://$SEED" OLC_REPO_BRANCH=main \
  OLC_EXIT_AFTER_REPO_SYNC=1 bash "$REPO_ROOT/install.sh" --update --ip 2>&1)"
DIRTY_AFTER="$(sha256sum "$DIRTY/README.md" | awk '{print $1}')"
if [[ "$DIRTY_BEFORE" == "$DIRTY_AFTER" && "$dirty_out" == *"dirty=1"* \
   && "$dirty_out" == *"автоматическое обновление репозитория пропущено"* ]]; then
  pass "dirty worktree сохранён байт-в-байт; reset не выполнялся"
else
  fail "dirty worktree был изменён или защитная ветка не сработала"
  echo "$dirty_out" | tail -20
fi

if grep -Fq 'chmod +x "$INSTALL_DIR"/scripts/*.sh' "$REPO_ROOT/install.sh"; then
  fail "install.sh must not alter executable bits of every tracked helper"
else
  pass "install.sh preserves tracked helper modes"
fi

if grep -Eq 'ls-remote origin main|pull( --quiet)? --ff-only origin main' "$BOOT" "$UPD"; then
  fail "update paths must not hardcode origin/main"
elif ! grep -q 'OLC_REPO_BRANCH' "$BOOT" || ! grep -q 'OLC_REPO_BRANCH' "$UPD"; then
  fail "update paths must accept the selected repository branch"
else
  pass "install-update and olc-update follow the selected/current branch"
fi

if [[ "$fails" -ne 0 ]]; then
  echo "[install-flags-test] FAIL after repository-safety regressions: $fails"
  exit 1
fi
echo "[install-flags-test] OK: fresh curl-menu и сохранение dirty worktree"
exit 0
