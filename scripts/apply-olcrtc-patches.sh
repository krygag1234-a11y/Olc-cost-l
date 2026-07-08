#!/usr/bin/env bash
# Apply VPS patches to cloned olcrtc + olcrtc-manager before build.
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
olc_git_safe_register "$REPO_ROOT"

OLCRTC_REPO="${OLCRTC_REPO:-/tmp/olcrtc-src}"
MGR_REPO="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}"
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

pin_manager_sha() {
  local pins="${UPSTREAM_PINS:-$REPO_ROOT/data/upstream-pins.json}"
  [[ -f "$pins" ]] || return 0
  jq -r '.["olcrtc-manager"].pinned_sha // empty' "$pins" 2>/dev/null || true
}

get_manager_source() {
  # Выбор источника manager: upstream или stable fork
  # --manager-stable → fork, --manager-latest → upstream, по умолчанию → upstream с pin
  if [[ "${OLC_MANAGER_STABLE:-0}" == "1" ]]; then
    echo "stable"
  elif [[ "${OLC_MANAGER_LATEST:-0}" == "1" ]]; then
    echo "latest"
  else
    echo "pinned"
  fi
}

clone_manager_from_fork() {
  local fork_url="https://github.com/krygag1234-a11y/local-panel-version.git"
  local fork_branch="stable-v1"
  log "clone manager from STABLE FORK: $fork_url ($fork_branch)"
  rm -rf "$MGR_REPO"
  if git clone -b "$fork_branch" --depth 1 "$fork_url" "$MGR_REPO" 2>/dev/null; then
    olc_git_safe_register "$MGR_REPO"
    log "✓ stable fork cloned successfully"
    return 0
  else
    log "ERROR: failed to clone stable fork"
    return 1
  fi
}

clone_repos() {
  if [[ -x /usr/local/go/bin/go ]]; then
    export PATH="/usr/local/go/bin:$PATH"
  fi
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
  local pin_sha
  pin_sha="$(pin_olcrtc_sha)"
  local mgr_pin_sha
  mgr_pin_sha="$(pin_manager_sha)"
  olc_git_safe_register "$OLCRTC_REPO"
  olc_git_safe_register "$MGR_REPO"
  if [[ -d "$OLCRTC_REPO/.git" ]]; then
    if [[ "${UPSTREAM_FRESH:-0}" == "1" ]]; then
      log "refresh olcrtc $OLCRTC_BRANCH"
      olc_git "$OLCRTC_REPO" fetch origin "$OLCRTC_BRANCH" --depth 1 2>/dev/null || \
        olc_git "$OLCRTC_REPO" fetch origin "$OLCRTC_BRANCH"
      olc_git "$OLCRTC_REPO" reset --hard "origin/$OLCRTC_BRANCH"
    elif [[ -n "$pin_sha" ]]; then
      log "checkout pinned olcrtc ${pin_sha:0:12}"
      olc_git "$OLCRTC_REPO" fetch origin "$pin_sha" --depth 1 2>/dev/null || \
        olc_git "$OLCRTC_REPO" fetch origin "$OLCRTC_BRANCH" --depth 50
      olc_git "$OLCRTC_REPO" reset --hard "$pin_sha" 2>/dev/null || true
    fi
  elif [[ -e "$OLCRTC_REPO" ]]; then
    rm -rf "$OLCRTC_REPO"
    git clone -b "$OLCRTC_BRANCH" --depth 1 \
      https://github.com/openlibrecommunity/olcrtc.git "$OLCRTC_REPO"
    olc_git_safe_register "$OLCRTC_REPO"
  else
    git clone -b "$OLCRTC_BRANCH" --depth 1 \
      https://github.com/openlibrecommunity/olcrtc.git "$OLCRTC_REPO"
    olc_git_safe_register "$OLCRTC_REPO"
  fi
  if [[ -d "$MGR_REPO/.git" ]]; then
    log "reset manager to clean state"
    olc_git "$MGR_REPO" reset --hard HEAD 2>/dev/null || true
    olc_git "$MGR_REPO" clean -fd 2>/dev/null || true
    
    # Проверяем, это stable fork или upstream
    local mgr_remote
    mgr_remote="$(olc_git "$MGR_REPO" remote get-url origin 2>/dev/null || true)"
    local mgr_source
    mgr_source="$(get_manager_source)"
    
    if [[ "$mgr_remote" == *"local-panel-version"* ]]; then
      # Сейчас используется stable fork
      if [[ "$mgr_source" == "stable" ]]; then
        log "detected stable fork, keeping as-is"
      else
        log "switching from stable fork to upstream"
        rm -rf "$MGR_REPO"
        git clone --depth 1 https://github.com/BigDaddy3334/olcrtc-manager-panel.git "$MGR_REPO"
        olc_git_safe_register "$MGR_REPO"
        if [[ "$mgr_source" == "pinned" && -n "$mgr_pin_sha" ]]; then
          log "checkout pinned manager ${mgr_pin_sha:0:12}"
          olc_git "$MGR_REPO" fetch origin "$mgr_pin_sha" --depth 1 2>/dev/null || \
            olc_git "$MGR_REPO" fetch origin main --depth 50
          olc_git "$MGR_REPO" reset --hard "$mgr_pin_sha" 2>/dev/null || true
        fi
      fi
    elif [[ "$mgr_source" == "stable" ]]; then
      log "switching to stable fork"
      clone_manager_from_fork || exit 1
    elif [[ -n "$mgr_pin_sha" && "$mgr_source" == "pinned" ]]; then
      log "checkout pinned manager ${mgr_pin_sha:0:12}"
      olc_git "$MGR_REPO" fetch origin "$mgr_pin_sha" --depth 1 2>/dev/null || \
        olc_git "$MGR_REPO" fetch origin main --depth 50
      olc_git "$MGR_REPO" reset --hard "$mgr_pin_sha" 2>/dev/null || true
    elif [[ "${UPSTREAM_FRESH:-0}" == "1" || "$mgr_source" == "latest" ]]; then
      log "refresh manager main (latest)"
      olc_git "$MGR_REPO" fetch origin main --depth 1 2>/dev/null || \
        olc_git "$MGR_REPO" fetch origin main
      olc_git "$MGR_REPO" reset --hard origin/main
    fi
  elif [[ -e "$MGR_REPO" ]]; then
    rm -rf "$MGR_REPO"
    git clone --depth 1 https://github.com/BigDaddy3334/olcrtc-manager-panel.git "$MGR_REPO"
    olc_git_safe_register "$MGR_REPO"
    if [[ -n "$mgr_pin_sha" ]]; then
      log "checkout pinned manager ${mgr_pin_sha:0:12}"
      olc_git "$MGR_REPO" fetch origin "$mgr_pin_sha" --depth 1 2>/dev/null || \
        olc_git "$MGR_REPO" fetch origin main --depth 50
      olc_git "$MGR_REPO" reset --hard "$mgr_pin_sha" 2>/dev/null || true
    fi
  else
    local mgr_source
    mgr_source="$(get_manager_source)"
    if [[ "$mgr_source" == "stable" ]]; then
      clone_manager_from_fork || {
        log "ERROR: stable fork failed, exiting"
        exit 1
      }
    else
      git clone --depth 1 https://github.com/BigDaddy3334/olcrtc-manager-panel.git "$MGR_REPO"
      olc_git_safe_register "$MGR_REPO"
      if [[ -n "$mgr_pin_sha" && "$mgr_source" != "latest" ]]; then
        log "checkout pinned manager ${mgr_pin_sha:0:12}"
        olc_git "$MGR_REPO" fetch origin "$mgr_pin_sha" --depth 1 2>/dev/null || \
          olc_git "$MGR_REPO" fetch origin main --depth 50
        olc_git "$MGR_REPO" reset --hard "$mgr_pin_sha" 2>/dev/null || true
      fi
    fi
  fi
  if [[ ! -f "$MGR_REPO/cmd/olcrtc-manager/main.go" ]]; then
    log "WARN: manager clone incomplete (нет main.go) — trying stable fork fallback"
    if clone_manager_from_fork; then
      log "✓ fallback to stable fork successful"
    else
      log "ERROR: both upstream and fork failed"
      exit 1
    fi
  fi
}

apply_olcrtc() {
  tui_spinner_start "Применение патчей для olcrtc-server (11 патчей)"
  (cd "$OLCRTC_REPO" && git checkout -f "$OLCRTC_BRANCH" 2>/dev/null || true)
  find "$OLCRTC_REPO" -name '*.rej' -o -name '*.orig' 2>/dev/null | xargs -r rm -f
  install -d "$OLCRTC_REPO/internal/routing"
  install -m 0644 "$PATCH_DIR/olcrtc-routing-cidr.go" "$OLCRTC_REPO/internal/routing/cidr.go"
  install -m 0644 "$PATCH_DIR/olcrtc-routing-domains.go" "$OLCRTC_REPO/internal/routing/domains.go"
  bash "$SCRIPT_DIR/patch-olcrtc-core.sh" "$OLCRTC_REPO"
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

apply_manager() {
  tui_spinner_start "Применение патчей для olcrtc-manager (132 патча)"
  find "$MGR_REPO" -name '*.rej' -o -name '*.orig' 2>/dev/null | xargs -r rm -f
  # Always run idempotent core patch (upstream main may already have logs API partial)
  bash "$SCRIPT_DIR/patch-olcrtc-manager-core.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go" || true
  if ! grep -q 'exitProxyReachable' "$MGR_REPO/cmd/olcrtc-manager/main.go" 2>/dev/null; then
    if [[ -f "$PATCH_DIR/olcrtc-manager-main.go.patch" ]]; then
      if ! (cd "$MGR_REPO" && patch -p1 --forward -N --batch <"$PATCH_DIR/olcrtc-manager-main.go.patch" >/dev/null 2>&1); then
        if declare -f olc_patch_skip_msg >/dev/null 2>&1; then
          olc_patch_skip_msg
        else
          tui_spinner_stop
          tui_log_warning "skip olcrtc-manager-main.go.patch (already applied or upstream mismatch)"
          tui_spinner_start "Продолжение патчинга"
        fi
      fi
    fi
    bash "$SCRIPT_DIR/patch-olcrtc-manager-core.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  fi
  bash "$SCRIPT_DIR/patch-olcrtc-manager-socks.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-domains.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-link-direct.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-default-link-tor.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-sessions.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-host-network.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-vps-extras.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-input-guard.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-room-validate.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-features.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-webtunnel-status-fix.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-capabilities.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-component-settings.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-component-settings-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-component-settings-v3.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-olcrtc-settings.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-olcrtc-settings-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-profiles.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-profiles-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-status-api.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-notifications.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-go-fixes.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-project-status.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-project-status-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-project-status-v3.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-pool-job.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-pool-job-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-component-settings-v4.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-component-settings-v5.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-update-guard-v1.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-notification-settings.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-backend-v4.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-backend-v4-fix.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-jitsi-preflight-v1.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-jitsi-preflight-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-jitsi-preflight-v3.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-jitsi-preflight-v4.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-git-safe-dir.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-releases-check.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go" || true
  bash "$SCRIPT_DIR/patch-olcrtc-manager-releases-check-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go" || true
  bash "$SCRIPT_DIR/patch-olcrtc-manager-releases-check-v3.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go" || true
  bash "$SCRIPT_DIR/patch-olcrtc-manager-project-stack-fix.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-settings-actions.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-room-binding.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-runtime-dir.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v1.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v3.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v4.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v5.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v6.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v7.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v8.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v9.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v10.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v11.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v12.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v13.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v14-routes.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v15.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v16-bridge-pool-log.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v17.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-core.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go" 2>/dev/null || true
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-link.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-transports.sh" \
    "$MGR_REPO/src/main.tsx" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-vp8-defaults.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-features-split-tolerant.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-features-api-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-host-sync.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-stop-action.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-features.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-features-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-header-network.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-v3.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-capabilities.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-safe-state.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-room-hint.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-settings-forms.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-settings-forms-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-phase456-ui.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-v5.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-v6.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-v7.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-v8.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-v9.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-v10.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-bridges-types-fix.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-bridge-status-ui.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-bridge-types-persist.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-bridge-list-cards-ui.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-jitsi-preflight-v1.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-jitsi-preflight-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-jitsi-preflight-v3.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-logs-verbose-v1.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v1.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-fixes.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v3.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v4.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-project-ui-fix.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-header-layout.sh" "$MGR_REPO/src/main.tsx" || true
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-releases-ui.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-releases-ui-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-project-ui-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-warp-feature.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-warp-settings-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-components-jobs-v2.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-components-jobs-v3.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-warp.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-ui-warp-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-components-jobs-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-components-jobs-ui-ttl.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-roadmap-finish-v1.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-roadmap-finish-v2.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-pending-locations-v1.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-stop-button.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v6.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v7.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v8.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v10.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v11.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v12.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v13.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v15.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v16.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v17.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v17-settings-layout.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v20.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v21.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v22.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v22-room-carrier.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v24-fix-component-installed.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-hotfix-v23.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-features-logs.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-async-delete.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-hotfix-v24-lang-defaults.sh" "$MGR_REPO"
  # Патчим эталон панели перед копированием (добавляем randomization UI)
  bash "$SCRIPT_DIR/patch-golden-panel-randomization-ui.sh"
  # Эталон панели — финальное выравнивание UI и main.go (поверх всех hotfix).
  bash "$SCRIPT_DIR/apply-golden-panel.sh" "$MGR_REPO"
  # Subscription randomization must run after golden-panel because golden-panel rewrites main.go.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-subscription-randomization.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-subscription-api.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  # Fix addon log resolution (correct file paths + journald fallback).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-feature-logs-fix.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  # Server-side autologi (auto-refresh logs) setting + endpoint.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-autologi-api.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  # Phase 1: per-bridge health API (join active bridges.conf with health TSV) + probe_now action.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-health-api.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  # Phase 1: bridge sources API + init on startup + legacy migration.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-bridge-sources-api.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-subscription-ui.sh" "$MGR_REPO/src/main.tsx"
  # Sync global-randomization state across subscription/selective panels + client cards (instant, no polling lag).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-randomization-sync.sh" "$MGR_REPO/src/main.tsx"
  # Disable addon "Логи" button when the addon is OFF.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-feature-logs-guard.sh" "$MGR_REPO/src/main.tsx"
  # Autologi UI + unified LIVE across log modals + panel-expand memory.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-autologi-ui.sh" "$MGR_REPO/src/main.tsx"
  # Polish: hide log-source path label in addon log modal.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-logs-polish.sh" "$MGR_REPO/src/main.tsx"
  # Remember + restore whichever modal was open across a page reload.
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-modal-memory.sh" "$MGR_REPO/src/main.tsx"
  # Resilient feature-toggle fetch (survives the deferred manager restart; no stuck buttons).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-toggle-resilient.sh" "$MGR_REPO/src/main.tsx"
  # Clarify + restructure addon settings modals (intro banner, sections, captions).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-addon-settings-ui.sh" "$MGR_REPO/src/main.tsx"
  # Phase 0: autosave in addon settings modal (no Save button; debounce + on-close/unload).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-addon-settings-autosave.sh" "$MGR_REPO/src/main.tsx"
  # Phase 0: autosave in general settings modal (validated; save on close/unload).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-general-settings-autosave.sh" "$MGR_REPO/src/main.tsx"
  # Phase 1: per-bridge health list UI (uses new backend 'health' field + probe_now).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-bridge-health-ui.sh" "$MGR_REPO/src/main.tsx"
  # Phase 1: bridge sources management UI (toggle/add/remove sources inline).
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-bridge-sources-ui.sh" "$MGR_REPO/src/main.tsx"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-postcss.sh" "$MGR_REPO"
  if [[ -f "$MGR_REPO/package.json" ]]; then
    if ! command -v npm >/dev/null 2>&1; then
      log "WARN: npm missing — install nodejs/npm then re-run apply-olcrtc-patches.sh (admin UI will be stale)"
    else
      log "build manager admin UI (web/dist)"
      rm -rf "$MGR_REPO/web/dist"
      run_quiet "npm install (manager UI)" bash -c 'cd "$1" && npm ci 2>/dev/null || npm install' _ "$MGR_REPO"
      run_quiet "npm build (manager UI)" bash -c 'cd "$1" && npm run build' _ "$MGR_REPO" || { log "ERROR: admin UI build failed — fix npm and retry"; exit 1; }
      if [[ -x "$SCRIPT_DIR/olc-panel-verify.sh" ]]; then
        bash "$SCRIPT_DIR/olc-panel-verify.sh" || log "WARN: panel-verify — см. отличия выше"
      else
        log "WARN: olc-panel-verify.sh не найден — пропуск проверки эталона"
      fi
    fi
  fi
  # /api/logs without trailing slash — upstream main often has logsHandler already
  tui_spinner_ok
}

build_binaries() {
  local rc=0
  if [[ -x /usr/local/go/bin/go ]]; then
    export PATH="/usr/local/go/bin:$PATH"
  fi
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
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
  tui_spinner_start "Сборка olcrtc ($(go version 2>/dev/null | awk '{print $3}' || echo 'go'))"
  olc_run_quiet_with_progress "сборка olcrtc" "${OLC_PATCH_LOG:-/var/log/olcrtc-apply-patches.log}" \
    bash -c 'cd "$1" && go build -o /usr/local/bin/olcrtc ./cmd/olcrtc' _ "$OLCRTC_REPO" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    tui_spinner_fail
    tui_log_error "olcrtc build failed (rc=$rc) — проверьте место на диске: df -h /"
    show_failure_logs_hint
    return "$rc"
  fi
  tui_spinner_ok
  
  install -d /var/lib/olcrtc
  date -Is > /var/lib/olcrtc/.split-routing-reload
  
  tui_spinner_start "Сборка olcrtc-manager"
  olc_run_quiet_with_progress "сборка olcrtc-manager" "${OLC_PATCH_LOG:-/var/log/olcrtc-apply-patches.log}" \
    bash -c 'cd "$1" && go build -o /usr/local/bin/olcrtc-manager ./cmd/olcrtc-manager' _ "$MGR_REPO" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    tui_spinner_fail
    tui_log_error "olcrtc-manager build failed (rc=$rc)"
    show_failure_logs_hint
    return "$rc"
  fi
  tui_spinner_ok
}

clone_repos
run_quiet "apply olcrtc patches" apply_olcrtc
run_quiet "apply manager patches + UI" apply_manager
if [[ "${BUILD:-1}" == "1" ]]; then
  bash "$SCRIPT_DIR/install-go-toolchain.sh" 2>/dev/null || true
  build_binaries || exit 1
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
