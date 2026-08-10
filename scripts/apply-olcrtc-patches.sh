#!/usr/bin/env bash
# Apply VPS patches to cloned OlcRTC core and build the vendored manager.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PATCH_DIR="${PATCH_DIR:-$REPO_ROOT/patches}"
# shellcheck source=lib-tui.sh
source "$SCRIPT_DIR/lib-tui.sh"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"
# shellcheck source=lib-git-safe.sh
source "$SCRIPT_DIR/lib-git-safe.sh"
# shellcheck source=lib-cache-cleanup.sh
source "$SCRIPT_DIR/lib-cache-cleanup.sh"
# shellcheck source=lib-olc-ru.sh
source "$SCRIPT_DIR/lib-olc-ru.sh"
# shellcheck source=lib-disk-preflight.sh
source "$SCRIPT_DIR/lib-disk-preflight.sh"
# shellcheck source=lib-install-state.sh
source "$SCRIPT_DIR/lib-install-state.sh" 2>/dev/null || true
olc_git_safe_register "$REPO_ROOT"

OLCRTC_REPO="${OLCRTC_REPO:-/tmp/olcrtc-src}"
MGR_REPO="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}"
VENDORED_MANAGER_SOURCE="${OLC_VENDORED_MANAGER_SOURCE:-$REPO_ROOT/components/olcrtc-manager}"


prepare_vendored_manager() {
  [[ -f "$VENDORED_MANAGER_SOURCE/cmd/olcrtc-manager/main.go" ]] || {
    echo "vendored manager source is missing: $VENDORED_MANAGER_SOURCE" >&2
    return 1
  }
  [[ "$MGR_REPO" != "$VENDORED_MANAGER_SOURCE" ]] || {
    echo "OLCRTC_MGR_REPO must be a temporary build directory, not the vendored source" >&2
    return 1
  }
  log "prepare vendored manager source: $VENDORED_MANAGER_SOURCE"
  # A developer checkout may legitimately contain node_modules after npm test.
  # Validate its tracked/source content, then copy only reproducible inputs into
  # the isolated build directory and enforce the strict no-build-state rule there.
  OLC_ALLOW_VENDORED_BUILD_STATE=1 \
    bash "$SCRIPT_DIR/verify-vendored-manager.sh" "$VENDORED_MANAGER_SOURCE"
  rm -rf "$MGR_REPO"
  install -d "$MGR_REPO"
  tar -C "$VENDORED_MANAGER_SOURCE" \
    --exclude='./.git' --exclude='./node_modules' \
    --exclude='*.bak' --exclude='*.bak-*' \
    --exclude='*.orig' --exclude='*.rej' \
    -cf - . | tar -C "$MGR_REPO" -xf -
  bash "$SCRIPT_DIR/verify-vendored-manager.sh" "$MGR_REPO"
  if find "$MGR_REPO" -type d \( -name .git -o -name node_modules \) -print -quit | grep -q .; then
    echo "temporary vendored manager copy contains forbidden build state" >&2
    return 1
  fi
}
safety_validate_git_build_dir "$OLCRTC_REPO" OLCRTC_REPO
safety_validate_git_build_dir "$MGR_REPO" OLCRTC_MGR_REPO
if [[ -z "${OLCRTC_BRANCH:-}" ]] && [[ -f "$REPO_ROOT/data/upstream-pins.json" ]]; then
  OLCRTC_BRANCH="$(jq -r '.olcrtc.branch // "master"' "$REPO_ROOT/data/upstream-pins.json")"
fi
OLCRTC_BRANCH="${OLCRTC_BRANCH:-master}"

log() { tui_log_step "$*"; }

run_quiet() {
  local label="$1"
  shift
  local log_dir="${OLC_PATCH_LOG_DIR:-/var/log}"
  local log_file="${OLC_PATCH_LOG:-$log_dir/olcrtc-apply-patches.log}"
  if [[ "${OLC_VERBOSE_INSTALL:-0}" == "1" ]]; then
    log "$label"
    "$@"
    return
  fi
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  log "$label (лог: $log_file)"
  if "$@" >>"$log_file" 2>&1; then
    return 0
  fi
  local rc=$?
  log "ERROR: $label failed (rc=$rc); последние строки $log_file:"
  tail -40 "$log_file" 2>/dev/null || true
  return "$rc"
}

show_failure_logs_hint() {
  local main_log="${OLC_PATCH_LOG:-/var/log/olcrtc-apply-patches.log}"
  log "Диагностика:"
  log "  sudo tail -n 80 $main_log"
  log "  sudo tail -n 80 /var/log/olcrtc-split-update.log"
  log "  sudo tail -n 80 /var/log/olcrtc-zapret-sync.log"
}

pin_olcrtc_sha() {
  local pins="${UPSTREAM_PINS:-$REPO_ROOT/data/upstream-pins.json}"
  [[ -f "$pins" ]] || return 0
  jq -r '.olcrtc.pinned_sha // empty' "$pins" 2>/dev/null || true
}


clone_repos() {
  _olc_substep "Клонирование репозиториев" 2>/dev/null || true
  if [[ -x /usr/local/go/bin/go ]]; then
    export PATH="/usr/local/go/bin:$PATH"
  fi
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
  local pin_sha
  pin_sha="$(pin_olcrtc_sha)"
  olc_git_safe_register "$OLCRTC_REPO"
  olc_git_safe_register "$MGR_REPO"
  # --- olcrtc core: ГАРАНТИРОВАННО приводим к ПИНУ (Урок 69). Раньше fresh-clone
  # (elif -e / else) игнорировал пин → master, а `reset --hard <pin> || true`
  # молча оставлял чужой код. master дрейфует и ломает якоря наших патчей, что
  # критично для крипто-патчей. Теперь: клон при отсутствии, затем fetch пина по
  # ПОЛНОМУ SHA (short SHA fetch НЕ работает) + reset --hard; провал = ЖЁСТКАЯ
  # ошибка (set -e прервёт сборку, старый бинарь останется — свап в конце).
  # UPSTREAM_FRESH=1 — осознанный переход на свежий master (для обновления пина).
  if [[ ! -d "$OLCRTC_REPO/.git" ]]; then
    rm -rf "$OLCRTC_REPO"
    git clone --depth 1 https://github.com/openlibrecommunity/olcrtc.git "$OLCRTC_REPO"
    olc_git_safe_register "$OLCRTC_REPO"
  fi
  if [[ "${UPSTREAM_FRESH:-0}" == "1" ]]; then
    log "refresh olcrtc $OLCRTC_BRANCH (UPSTREAM_FRESH=1)"
    olc_git "$OLCRTC_REPO" fetch origin "$OLCRTC_BRANCH" --depth 1
    olc_git "$OLCRTC_REPO" reset --hard "origin/$OLCRTC_BRANCH"
    olc_git "$OLCRTC_REPO" clean -fd 2>/dev/null || true
  elif [[ -n "$pin_sha" ]]; then
    log "checkout pinned olcrtc ${pin_sha:0:12}"
    if ! olc_git "$OLCRTC_REPO" cat-file -e "${pin_sha}^{commit}" 2>/dev/null; then
      olc_git "$OLCRTC_REPO" fetch origin "$pin_sha" --depth 1 2>/dev/null || \
        olc_git "$OLCRTC_REPO" fetch origin "$OLCRTC_BRANCH"
    fi
    if ! olc_git "$OLCRTC_REPO" reset --hard "$pin_sha"; then
      log "FATAL: cannot checkout pinned olcrtc $pin_sha — refusing to silently build a different core (Урок 69)"
      return 1
    fi
    olc_git "$OLCRTC_REPO" clean -fd 2>/dev/null || true
  else
    log "no olcrtc pin configured; tracking $OLCRTC_BRANCH"
    olc_git "$OLCRTC_REPO" fetch origin "$OLCRTC_BRANCH" --depth 1
    olc_git "$OLCRTC_REPO" reset --hard "origin/$OLCRTC_BRANCH"
  fi

  prepare_vendored_manager
}

apply_olcrtc() {
  _olc_substep "Применение патчей olcrtc" 2>/dev/null || true
  tui_spinner_start "Применение патчей для olcrtc-server (11 патчей)"
  (cd "$OLCRTC_REPO" && git checkout -f "$OLCRTC_BRANCH" 2>/dev/null || true)
  find "$OLCRTC_REPO" -name '*.rej' -o -name '*.orig' 2>/dev/null | xargs -r rm -f
  install -d "$OLCRTC_REPO/internal/routing"
  install -m 0644 "$PATCH_DIR/olcrtc-routing-cidr.go" "$OLCRTC_REPO/internal/routing/cidr.go"
  install -m 0644 "$PATCH_DIR/olcrtc-routing-domains.go" "$OLCRTC_REPO/internal/routing/domains.go"
  bash "$SCRIPT_DIR/patch-olcrtc-core.sh" "$OLCRTC_REPO"
  # Enforcement контроля доступа на подключении (safe-by-default AuthHook).
  bash "$SCRIPT_DIR/patch-olcrtc-core-access-hook.sh" "$OLCRTC_REPO"
  # Рандомизация ключей (эпик A), часть 1: multi-key в muxconn (ИНЕРТНА без alt-ключей). После access-hook.
  bash "$SCRIPT_DIR/patch-olcrtc-core-key-randomization.sh" "$OLCRTC_REPO"
  bash "$SCRIPT_DIR/patch-olcrtc-core-access-live-keyclass.sh" "$OLCRTC_REPO"
  bash "$SCRIPT_DIR/patch-olcrtc-server-domains.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-blocked-tor.sh" \
    "$OLCRTC_REPO/internal/server/server.go" \
    "$OLCRTC_REPO/internal/config/config.go" \
    "$OLCRTC_REPO/internal/app/session/session.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-force-tor.sh" \
    "$OLCRTC_REPO/internal/server/server.go" \
    "$OLCRTC_REPO/internal/config/config.go" \
    "$OLCRTC_REPO/internal/app/session/session.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-route-log.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-routing-reload.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-routing-reload-debounce.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-routing-reload-skip.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-routing-rwlock.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-tor-limits.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-reconnect-debounce.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-jitsi-no-smux-reconnect.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-jitsi-join-retry.sh" "$OLCRTC_REPO/internal/engine/jitsi/jitsi.go"
  bash "$SCRIPT_DIR/patch-olcrtc-jitsi-extras.sh" "$OLCRTC_REPO/internal/engine/jitsi/jitsi.go"
  # goolom: upstream master has correct backoff (2s) and maxReconnects (10).
  # Our old patches that changed those values are now noops / skip automatically.
  bash "$SCRIPT_DIR/patch-olcrtc-goolom-reconnect-stable.sh" "$OLCRTC_REPO/internal/engine/goolom"
  bash "$SCRIPT_DIR/patch-olcrtc-goolom-reconnect-no-early-callback.sh" "$OLCRTC_REPO/internal/engine/goolom/lifecycle.go"
  # datachannel payload: upstream master uses 12*1024 (conservative), keep it as-is
  : # no override needed — upstream master already has 12*1024
  run_quiet "go mod download (olcrtc)" bash -c 'cd "$1" && go mod download github.com/zarazaex69/j 2>/dev/null || go mod download' _ "$OLCRTC_REPO"
  bash "$SCRIPT_DIR/patch-j-xmpp-bind-fastfail.sh" "$OLCRTC_REPO"
  tui_spinner_ok
}


build_binaries() {
  _olc_substep "Подготовка к сборке" 2>/dev/null || true
  local rc=0
  if [[ -x /usr/local/go/bin/go ]]; then
    export PATH="/usr/local/go/bin:$PATH"
  fi
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
  # Transient systemd units may not define HOME, so Go cannot infer GOPATH.
  # Keep all Go state in explicit system paths instead of relying on HOME.
  export GOPATH="${GOPATH:-/var/cache/olc-go}"
  export GOMODCACHE="${GOMODCACHE:-$GOPATH/pkg/mod}"
  export GOCACHE="${GOCACHE:-/var/cache/go-build}"
  export GOTMPDIR="${GOTMPDIR:-/var/tmp/go-build-tmp}"
  mkdir -p "$GOPATH" "$GOMODCACHE" "$GOCACHE" "$GOTMPDIR" 2>/dev/null || true
  olc_preflight_build_space "сборка olcrtc + olcrtc-manager" || return 1
  local used_pct
  used_pct="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $5+0}' || echo 0)"
  if [[ "$used_pct" -ge 90 ]]; then
    log "WARN: диск заполнен на ${used_pct}% — очистка кэшей перед go build"
    if [[ "$used_pct" -ge 95 ]]; then
      OLC_KEEP_BUILD_CLONES=1 OLC_CLEAN_GO_MOD_CACHE=1 olc_cleanup_build_caches "apply-patches-pre-build-critical" || true
    else
      OLC_KEEP_BUILD_CLONES=1 olc_cleanup_build_caches "apply-patches-pre-build" || true
    fi
  fi

  # Параллельная сборка Go-бинарей для ускорения (экономия ~10-12s)
  _olc_substep "go build olcrtc + olcrtc-manager" 2>/dev/null || true
  tui_spinner_start "Параллельная сборка olcrtc + olcrtc-manager ($(go version 2>/dev/null | awk '{print $3}' || echo 'go'))"

  local olcrtc_log="/tmp/olcrtc-build-$$.log"
  local manager_log="/tmp/olcrtc-manager-build-$$.log"

  # Флаги оптимизации: -s -w убирают debug info, ускоряют линковку
  # ВАЖНО: кавычки вокруг переменной при использовании, чтобы -s -w парсились вместе
  local build_flags='-ldflags=-s -w'

  # Запустить обе сборки параллельно
  (cd "$OLCRTC_REPO" && go build -trimpath -buildvcs=false "$build_flags" -o /usr/local/bin/olcrtc ./cmd/olcrtc 2>&1 | tee "$olcrtc_log") &
  local olcrtc_pid=$!

  (cd "$MGR_REPO" && go build -trimpath -buildvcs=false "$build_flags" -o /usr/local/bin/olcrtc-manager ./cmd/olcrtc-manager 2>&1 | tee "$manager_log") &
  local manager_pid=$!

  # Ждать завершения обеих сборок
  local olcrtc_rc=0 manager_rc=0
  wait "$olcrtc_pid" || olcrtc_rc=$?
  wait "$manager_pid" || manager_rc=$?

  # Проверить результаты
  if [[ "$olcrtc_rc" -ne 0 ]]; then
    tui_spinner_fail
    tui_log_error "olcrtc build failed (rc=$olcrtc_rc)"
    cat "$olcrtc_log" >&2
    rm -f "$olcrtc_log" "$manager_log"
    return "$olcrtc_rc"
  fi

  if [[ "$manager_rc" -ne 0 ]]; then
    tui_spinner_fail
    tui_log_error "olcrtc-manager build failed (rc=$manager_rc)"
    cat "$manager_log" >&2
    rm -f "$olcrtc_log" "$manager_log"
    return "$manager_rc"
  fi

  rm -f "$olcrtc_log" "$manager_log"
  tui_spinner_ok

  install -d /var/lib/olcrtc
  date -Is > /var/lib/olcrtc/.split-routing-reload
}

# Vendored path has four real stages: sources, OlcRTC patches, source verification, parallel Go build.
if declare -f _olc_substep_reset >/dev/null 2>&1; then
  _olc_substep_reset 4
fi

clone_repos
run_quiet "apply olcrtc patches" apply_olcrtc
run_quiet "verify vendored manager + prebuilt UI" bash "$SCRIPT_DIR/verify-vendored-manager.sh" "$MGR_REPO"
if [[ "${OLC_PATCH_ONLY:-0}" == "1" ]]; then
  log "patch-only done"
  exit 0
fi
if [[ "${BUILD:-1}" == "1" ]]; then
  bash "$SCRIPT_DIR/install-go-toolchain.sh" 2>/dev/null || true
  build_binaries || tui_fatal "Сборка Go-бинарников (olcrtc/olcrtc-manager) завершилась с ошибкой" "Возможно: Go toolchain не установлен или GOPATH повреждён" "Проверьте: /usr/local/go/bin/go version && export GOTOOLCHAIN=auto"
fi
  install -m 0755 "$SCRIPT_DIR/olc-panel-update-run.sh" /usr/local/bin/olc-panel-update-run 2>/dev/null || true
  install -m 0755 "$SCRIPT_DIR/olc-error-scan.sh" /usr/local/bin/olc-error-scan 2>/dev/null || true
  install -m 0755 "$SCRIPT_DIR/olc-component-job.sh" /usr/local/bin/olc-component-job 2>/dev/null || true
  install -m 0755 "$SCRIPT_DIR/olc-component-remove.sh" /usr/local/bin/olc-component-remove 2>/dev/null || true
  install -m 0755 "$SCRIPT_DIR/olc-error-match.sh" /usr/local/bin/olc-error-match 2>/dev/null || true
  install -m 0755 "$SCRIPT_DIR/olc-zapret-apply-strategy.sh" /usr/local/bin/olc-zapret-apply-strategy 2>/dev/null || true
  if [[ "${OLC_CLEANUP_AFTER_BUILD:-1}" == "1" ]]; then
    olc_cleanup_build_caches "apply-patches"
  fi
  log "done"
