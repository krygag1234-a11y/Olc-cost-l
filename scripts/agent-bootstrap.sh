#!/usr/bin/env bash
# Flexible VPS deploy for OlcRTC + manager (patched) + optional Tor/split.
#
# Usage:
#   agent-bootstrap.sh --full              # clean VPS: deps + patched build + all services
#   agent-bootstrap.sh                     # config only (tor/panel already built)
#   agent-bootstrap.sh --no-tor            # иностранный VPS: только панель+olcrtc, без Tor/split/мостов
#   agent-bootstrap.sh --with-tor          # RU VPS: Tor + bridge pool + split (RU+CDN+плееры)
#   agent-bootstrap.sh --no-split          # RU VPS: Tor без списков direct (весь трафик через exit)
#   agent-bootstrap.sh --with-warp          # foreign VPS: WARP proxy вместо Tor
#   agent-bootstrap.sh --rebuild-only      # only apply patches + rebuild binaries
#   agent-bootstrap.sh --update            # git pull path: lists + patches + tor exit (no apt)
#   agent-bootstrap.sh --resume            # продолжить с последнего успешного шага
#   agent-bootstrap.sh --fresh-state       # удалить state и пройти все шаги заново
#   agent-bootstrap.sh --state             # показать текущее состояние установки
#   agent-bootstrap.sh --help
#
# Env: OLCRTC_ENABLE_TOR=0|1  OLCRTC_ENABLE_SPLIT=0|1  OLCRTC_RU_VPS=0|1  OLCRTC_BRANCH=fix/all (default from data/upstream-pins.json)
#      OLCRTC_RESUME=0|1  OLCRTC_FRESH=0|1  OLCRTC_FORCE_STEP=<step-name>
#      OLCRTC_SKIP_WEBTUNNEL=0|1  OLCRTC_ENABLE_ZAPRET=0|1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DOC="$REPO_ROOT/docs/VPS-SETUP.md"
PATCH_SCRIPT="$SCRIPT_DIR/apply-olcrtc-patches.sh"
export OLC_REPO_ROOT="$REPO_ROOT"

FULL=0
INCREMENTAL=0  # Доустановка - skip того что работает
ENABLE_TOR="${OLCRTC_ENABLE_TOR:-1}"
ENABLE_SPLIT="${OLCRTC_ENABLE_SPLIT:-1}"
ENABLE_WARP="${OLCRTC_ENABLE_WARP:-0}"
RU_VPS="${OLCRTC_RU_VPS:-1}"
PANEL_ACCESS="${OLCRTC_PANEL_ACCESS:-ip}"
PANEL_TLS="${OLCRTC_PANEL_TLS:-0}"
PANEL_LISTEN_ADDR="${OLCRTC_MANAGER_ADDR:-0.0.0.0}"
PANEL_ACCESS_EXPLICIT=0
REBUILD_ONLY=0
UPDATE=0
PROFILE_ID=""

# shellcheck source=lib-tui.sh
source "$SCRIPT_DIR/lib-tui.sh"
# shellcheck source=lib-olc-ru.sh
source "$SCRIPT_DIR/lib-olc-ru.sh"
log() {
  tui_log_step "$*"
}

# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"
# shellcheck source=lib-webtunnel-build.sh
source "$SCRIPT_DIR/lib-webtunnel-build.sh"
# shellcheck source=lib-install-state.sh
source "$SCRIPT_DIR/lib-install-state.sh"
# shellcheck source=lib-git-safe.sh
source "$SCRIPT_DIR/lib-git-safe.sh"
# shellcheck source=lib-olc-core.sh
source "$SCRIPT_DIR/lib-olc-core.sh"
# shellcheck source=lib-deploy-profile.sh
source "$SCRIPT_DIR/lib-deploy-profile.sh"
# shellcheck source=lib-disk-preflight.sh
source "$SCRIPT_DIR/lib-disk-preflight.sh"
# shellcheck source=lib-cache-cleanup.sh
source "$SCRIPT_DIR/lib-cache-cleanup.sh"
# shellcheck source=lib-vps-backup.sh
source "$SCRIPT_DIR/lib-vps-backup.sh"

# Hint shown on abort so user can `--resume` exactly the same invocation.
export OLCRTC_RESUME_HINT="--resume $*"
# Soft (non-fatal) steps: install proceeds even if these fail.
export OLCRTC_SOFT_STEPS="webtunnel,zapret,cron,sysctl,split,bridges,fetch-community-lists"

ensure_install_symlink() {
  safety_ensure_olcrtc_symlink "$REPO_ROOT"
  install_cli_symlinks
}

ensure_ui_build_deps() {
  if command -v npm >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    return 0
  fi
  tui_spinner_start "Установка nodejs/npm"
  apt-get update -qq 2>&1 >/dev/null
  apt-get install -y -qq nodejs npm 2>&1 >/dev/null
  tui_spinner_ok
}

usage() {
  sed -n '3,14p' "$0"
  echo ""
  echo "Patches: $REPO_ROOT/patches/PATCHES.md"
  echo "olcrtc:  master | panel: main | Olcbox: releases/tag/nightly"
  echo "Client:  https://github.com/alananisimov/olcbox/releases"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) 
      FULL=1
      # Если указан --full, инициализируем всё по умолчанию
      ENABLE_TOR=1
      ENABLE_SPLIT=1
      RU_VPS=1
      export OLCRTC_ENABLE_ZAPRET=1
      ENABLE_WARP=0
      ENABLE_BRIDGES=1
      ;;
    --tor) ENABLE_TOR=1; RU_VPS=1; FULL=1 ;;
    --split) ENABLE_SPLIT=1; RU_VPS=1; FULL=1 ;;
    --zapret) export OLCRTC_ENABLE_ZAPRET=1; RU_VPS=1; FULL=1 ;;
    --warp|--with-warp) ENABLE_WARP=1; ENABLE_TOR=0; ENABLE_SPLIT=0; ENABLE_BRIDGES=0; RU_VPS=0; FULL=1 ;;
    --bridges) ENABLE_BRIDGES=1; RU_VPS=1; FULL=1 ;;
    --no-tor|--foreign) ENABLE_TOR=0; ENABLE_SPLIT=0; ENABLE_BRIDGES=0; RU_VPS=0; ENABLE_WARP=0 ;;
    --no-split) ENABLE_SPLIT=0 ;;
    --no-zapret) export OLCRTC_ENABLE_ZAPRET=0 ;;
    --no-warp) ENABLE_WARP=0 ;;
    --no-bridges) ENABLE_BRIDGES=0 ;;
    --ru) RU_VPS=1; ENABLE_TOR=1; ENABLE_SPLIT=1; ENABLE_BRIDGES=1 ;;
    --ssh|--localhost|--local-panel) PANEL_ACCESS=ssh; PANEL_ACCESS_EXPLICIT=1 ;;
    --ip|--public-panel) PANEL_ACCESS=ip; PANEL_ACCESS_EXPLICIT=1 ;;
    --rebuild-only) REBUILD_ONLY=1 ;;
    --update) UPDATE=1 ;;
    --incremental) INCREMENTAL=1 ;;
    --resume) export OLCRTC_RESUME=1 ;;
    --fresh-state) export OLCRTC_FRESH=1 ;;
    --force-sha-update) export OLCRTC_FORCE_SHA_UPDATE=1 ;;
    --manager-stable) export OLC_MANAGER_STABLE=1 ;;
    --manager-latest) export OLC_MANAGER_LATEST=1 ;;
    --state) source "$SCRIPT_DIR/lib-install-state.sh"; state_show; exit 0 ;;
    --profile)
      PROFILE_ID="${2:-}"
      [[ -n "$PROFILE_ID" ]] || { echo "--profile requires profile id" >&2; exit 1; }
      shift 2
      continue
      ;;
    --write-profile) profile_from_flags "$ENABLE_TOR" "$ENABLE_SPLIT" "${OLCRTC_ENABLE_ZAPRET:-1}" "${ENABLE_BRIDGES:-1}" "$RU_VPS" "install.sh:${*:-}" "$ENABLE_WARP" "$PANEL_ACCESS"; profile_show; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

# Проверка конфликтов флагов
if [[ "${ENABLE_TOR:-0}" -eq 1 && "${ENABLE_WARP:-0}" -eq 1 ]]; then
  tui_log_error "Нельзя комбинировать Tor (--tor) и WARP (--warp). Выберите что-то одно."
  exit 1
fi
if [[ "${ENABLE_SPLIT:-0}" -eq 1 && "${ENABLE_TOR:-0}" -eq 0 ]]; then
  tui_log_error "--split требует установки Tor. Маршрутизация без Tor не имеет смысла."
  exit 1
fi
if [[ "${ENABLE_BRIDGES:-0}" -eq 1 && "${ENABLE_TOR:-0}" -eq 0 ]]; then
  tui_log_error "--bridges требует установки Tor. Маршрутизация без Tor не имеет смысла."
  exit 1
fi

if [[ -n "$PROFILE_ID" ]]; then
  profile_install_template "$PROFILE_ID"
fi

if [[ ! -f "$OLCRTC_DEPLOY_PROFILE" ]] && [[ "$UPDATE" -ne 1 ]]; then
  profile_from_flags "$ENABLE_TOR" "$ENABLE_SPLIT" "${OLCRTC_ENABLE_ZAPRET:-1}" 1 "$RU_VPS" "agent-bootstrap" "$ENABLE_WARP" "$PANEL_ACCESS"
fi

if [[ "$PANEL_ACCESS_EXPLICIT" -eq 1 ]]; then
  profile_set_panel_access "$PANEL_ACCESS"
fi

profile_apply_env

require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
}

install_deps() {
  log "Установка зависимостей (git, build-essential, golang${ENABLE_TOR:+, tor, obfs4})"
  local apt_log="/var/log/olcrtc-apt-install.log"
  : >"$apt_log"

  tui_log_info "Обновление списка пакетов..."
  apt-get update -qq >>"$apt_log" 2>&1

  tui_log_info "Установка базовых пакетов..."
  apt-get install -y -qq git curl build-essential golang-go jq ca-certificates >>"$apt_log" 2>&1 || true

  tui_log_info "Установка Node.js и npm..."
  apt-get install -y -qq patch nodejs npm >>"$apt_log" 2>&1 || true

  if [[ "${ENABLE_TOR:-0}" -eq 1 ]]; then
    tui_log_info "Установка Tor и плагинов обхода..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tor obfs4proxy snowflake-client apparmor-utils ffmpeg >>"$apt_log" 2>&1 || true
  fi

  tui_log_info "Установка Go toolchain..."
  bash "$SCRIPT_DIR/install-go-toolchain.sh" >>"$apt_log" 2>&1 || true

  export PATH="/usr/local/go/bin:${PATH:-}"
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
  tui_log_success "Зависимости установлены ($(go version 2>/dev/null | awk '{print $3}' || echo 'go'))"
  tui_log_info "  подробный лог: $apt_log"

  if [[ "$ENABLE_TOR" -eq 1 ]] && [[ ! -x /usr/bin/webtunnel-client ]]; then
    command -v go >/dev/null || apt-get install -y -qq golang-go >>"$apt_log" 2>&1
  fi
}


build_webtunnel() {
  [[ "$ENABLE_TOR" -eq 1 ]] || return 0
  log "webtunnel-client (optional — obfs4/snowflake work without it)"
  build_webtunnel_client log || true
}

setup_warp() {
  [[ "${ENABLE_WARP:-0}" -eq 1 ]] || { log "skip WARP (not in deploy profile)"; return 0; }
  bash "$SCRIPT_DIR/install-warp.sh"
  if [[ -f /etc/olcrtc-manager/features.env ]]; then
    # shellcheck disable=SC1091
    set -a; source /etc/olcrtc-manager/features.env; set +a
  fi
  if [[ "${OLCRTC_ENABLE_WARP:-0}" == "1" ]]; then
    bash "$SCRIPT_DIR/olc-feature.sh" warp on || true
  else
    log "warp: installed/updated; left disconnected (features.env WARP=0)"
  fi
}

setup_tor() {
  [[ "$ENABLE_TOR" -eq 1 ]] || { log "skip Tor (--no-tor / foreign VPS)"; return 0; }
  bash "$SCRIPT_DIR/secure-local-tor.sh" 2>/dev/null || true
  bash "$SCRIPT_DIR/install-tor-pluggable-transports.sh" 2>/dev/null || true
  local btypes
  btypes="$(effective_bridge_types "${BRIDGE_TYPES:-obfs4}")"
  if ! webtunnel_client_ready; then
    log "Tor bridges: obfs4-only (webtunnel-client not built — gitlab often times out from RU)"
  else
    log "Tor bridges pool ($btypes)"
  fi
  export BRIDGE_TYPES="$btypes"
  bash "$SCRIPT_DIR/fetch-bridge-extra-sources.sh" 2>/dev/null || \
    bash "$SCRIPT_DIR/tor-bridge-pool.sh" --fetch --url-only --jobs 6 --target 12 --types "$btypes" || \
    bash "$SCRIPT_DIR/tor-bridge-rotate.sh" || true
  bash "$SCRIPT_DIR/tor-bridge-pool.sh" --apply --types "$btypes" 2>/dev/null || true
  # Respect features.env: maintenance may run, but don't force-start if user toggled off.
  if [[ -f /etc/olcrtc-manager/features.env ]]; then
    # shellcheck disable=SC1091
    set -a; source /etc/olcrtc-manager/features.env; set +a
  fi
  if [[ "${OLCRTC_ENABLE_TOR:-1}" == "1" ]]; then
    systemctl enable tor@default.service
    systemctl restart tor@default.service || true
  else
    systemctl stop tor@default.service 2>/dev/null || true
    systemctl disable tor@default.service 2>/dev/null || true
    log "tor: pools refreshed; service left stopped (features.env TOR=0)"
  fi
  systemctl enable olcrtc-tor-bridge-pool.timer olcrtc-tor-bridge-monitor.timer \
    olcrtc-tor-bridge-deep.timer 2>/dev/null || true
  bash "$SCRIPT_DIR/configure-tor-exit.sh" 2>/dev/null || true
}

setup_split_routing() {
  if [[ "$RU_VPS" -ne 1 || "$ENABLE_SPLIT" -ne 1 || "$ENABLE_TOR" -ne 1 ]]; then
    log "skip split lists (foreign VPS or --no-split or --no-tor)"
    return 0
  fi
  log "split: подготовка списков может занять 2-5 минут; если терминал молчит — процесс всё ещё работает"
  local quick=0
  local max_age="${OLCRTC_SPLIT_LISTS_MAX_AGE:-604800}"
  if [[ "$UPDATE" -eq 1 ]] && [[ "${OLCRTC_SPLIT_FORCE_REFRESH:-0}" != "1" ]] && [[ -s /var/lib/olcrtc/ru-direct-domains.txt ]]; then
    local age=$(( $(date +%s) - $(stat -c %Y /var/lib/olcrtc/ru-direct-domains.txt 2>/dev/null || echo 0) ))
    if [[ "$age" -lt "$max_age" ]]; then
      quick=1
      log "split: quick update (lists ${age}s old) — OLCRTC_SPLIT_FORCE_REFRESH=1 for full refresh"
    fi
  fi
  if [[ "$quick" -eq 1 ]]; then
    olc_run_quiet_with_progress "обновление split-списков" "/var/log/olcrtc-split-update.log" env \
      OLCRTC_RU_VPS=1 OLCRTC_SKIP_GEOSITE_FETCH=1 OLCRTC_SKIP_BLOCKED_TOR_FETCH=1 \
      bash "$SCRIPT_DIR/setup-split-ru.sh" --quick
  else
    olc_run_quiet_with_progress "полное обновление split-списков" "/var/log/olcrtc-split-update.log" env \
      OLCRTC_RU_VPS=1 bash "$SCRIPT_DIR/setup-split-ru.sh"
  fi
}

setup_sysctl() {
  local f=/etc/sysctl.d/99-olcrtc-performance.conf
  safety_path_allowed "$f" || return 1
  cat >"$f" <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.core.rmem_default=2097152
net.core.wmem_default=2097152
net.ipv4.tcp_rmem=4096 1048576 33554432
net.ipv4.tcp_wmem=4096 1048576 33554432
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.core.netdev_max_backlog=250000
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
EOF
  # Only our drop-in — do not reload unrelated sysctl.d on shared hosts
  sysctl -p "$f" >/dev/null 2>&1 || true
}

install_systemd_units() {
  local scripts="${REPO_ROOT}/scripts"
  
  # Note: olcrtc.service is NOT needed - olcrtc-manager spawns olcrtc processes per-client
  # Upstream BigDaddy3334/olcrtc-manager-panel doesn't provide olcrtc.service
  
  # Install olcrtc-manager service
  cp "$REPO_ROOT/packaging/systemd/olcrtc-manager.service" /etc/systemd/system/olcrtc-manager.service
  sed -i "s/^Environment=OLCRTC_MANAGER_ADDR=.*/Environment=OLCRTC_MANAGER_ADDR=${PANEL_LISTEN_ADDR:-0.0.0.0}/" \
    /etc/systemd/system/olcrtc-manager.service
  if [[ "$ENABLE_TOR" -ne 1 ]]; then
    sed -i '/tor@default\.service/d; /^Environment=OLCRTC_EXIT_PROXY=/d' \
      /etc/systemd/system/olcrtc-manager.service
  fi

  for u in olcrtc-tor-bridge-pool olcrtc-tor-bridge-monitor olcrtc-tor-bridge-deep; do
    [[ "$ENABLE_TOR" -eq 1 ]] || continue
    sed "s|@OLC_SCRIPTS@|${scripts}|g" \
      "$REPO_ROOT/packaging/systemd/${u}.service" \
      >/etc/systemd/system/${u}.service
    install -m 0644 "$REPO_ROOT/packaging/systemd/${u}.timer" \
      "/etc/systemd/system/${u}.timer"
  done

  cat >/etc/systemd/system/olcrtc-network-recovery.service <<EOF
[Unit]
Description=OlcRTC network recovery
After=network-online.target

[Service]
Type=oneshot
ExecStart=${scripts}/network-recovery.sh
EOF
}

setup_systemd() {
  install -d /etc/olcrtc-manager
  [[ -f /etc/olcrtc-manager/config.json ]] || cat >/etc/olcrtc-manager/config.json <<'EOF'
{"version":1,"name":"olcrtc-vps","port":8888,"clients":[]}
EOF
  install_systemd_units
  systemctl daemon-reload
  # Note: only olcrtc-manager.service is needed (it spawns olcrtc processes)
  systemctl enable olcrtc-manager.service olcrtc-network-recovery.service
}

install_cli_symlinks() {
  local s
  for s in olc-feature.sh olc-update.sh olc-sync-panel-host.sh olc-split-analyze.sh olc-vps-backup.sh olc-vps-snapshot.sh olc-panel-verify.sh olc-panel-refresh-local.sh olc-cleanup-caches.sh olc-purge.sh; do
    [[ -f "$SCRIPT_DIR/$s" ]] || continue
    ln -sfn "$SCRIPT_DIR/$s" "/usr/local/bin/${s%.sh}" 2>/dev/null || true
  done
}

setup_cron() {
  install_cli_symlinks
  local cronf=/etc/cron.d/olcrtc-healthcheck
  safety_path_allowed "$cronf" || return 1
  cat >"$cronf" <<EOF
# Olc-cost-l — healthcheck (safe to delete this file to disable)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/10 * * * * root ${REPO_ROOT}/scripts/healthcheck.sh >>/var/log/olcrtc-healthcheck.log 2>&1
# After split list refresh (Sun 04:10) — sync zapret exclusions without full reinstall
10 4 * * 0 root ${REPO_ROOT}/scripts/setup-split-ru.sh >>/var/log/olcrtc-zapret-sync.log 2>&1
EOF
  chmod 0644 "$cronf"
  # Remove legacy line from /etc/crontab if present (older deploys)
  if grep -qF 'healthcheck.sh' /etc/crontab 2>/dev/null; then
    sed -i '\|healthcheck\.sh|d' /etc/crontab
  fi
}

# --- main ---
require_root

# Show TUI banner
tui_clear
tui_banner "Olc-cost-l Bootstrap"
if [[ $FULL -eq 1 ]]; then
  tui_log_info "Режим: Полная установка (зависимости + сборка + сервисы)"
elif [[ $UPDATE -eq 1 ]]; then
  tui_log_info "Режим: Обновление (git pull + пересборка)"
elif [[ $INCREMENTAL -eq 1 ]]; then
  tui_log_info "Режим: Доустановка недостающих компонентов"
elif [[ $REBUILD_ONLY -eq 1 ]]; then
  tui_log_info "Режим: Только пересборка бинарей"
else
  tui_log_info "Режим: Конфигурация сервисов"
fi
tui_divider

olc_preflight_disk_space "agent-bootstrap" || exit 1
olc_preflight_vps_backup "agent-bootstrap" || true
olc_git_safe_register "${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
ensure_install_symlink
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
state_init

ensure_panel_jitsi_tls() {
  local env=/etc/olcrtc-manager/panel.env
  local config_dir=/etc/olcrtc-manager
  local tls_cert="$config_dir/tls.crt"
  local tls_key="$config_dir/tls.key"

  install -d "$config_dir"
  touch "$env"

  safety_panel_env_set "$env" OLCRTC_JITSI_INSECURE_TLS 1
  safety_panel_env_set "$env" OLCRTC_MANAGER_ADDR "${PANEL_LISTEN_ADDR:-0.0.0.0}"
  safety_panel_env_set "$env" OLCRTC_PANEL_ACCESS "${PANEL_ACCESS:-ip}"

  # HTTPS support: generate self-signed cert if enabled
  local panel_tls="${PANEL_TLS:-0}"
  if [[ "$panel_tls" == "1" ]]; then
    if [[ ! -f "$tls_cert" ]] || [[ ! -f "$tls_key" ]]; then
      log "Generating self-signed TLS certificate for panel..."
      local cert_ip="${PANEL_CERT_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
      openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$tls_key" -out "$tls_cert" \
        -days 365 -subj "/CN=${cert_ip}" \
        -addext "subjectAltName=IP:${cert_ip}" 2>/dev/null || {
        log "WARNING: openssl cert generation failed, falling back to HTTP"
        panel_tls=0
      }
      chmod 600 "$tls_key" "$tls_cert" 2>/dev/null || true
    else
      log "Using existing TLS certificate: $tls_cert"
    fi

    if [[ "$panel_tls" == "1" ]]; then
      safety_panel_env_set "$env" OLCRTC_MANAGER_TLS_CERT "$tls_cert"
      safety_panel_env_set "$env" OLCRTC_MANAGER_TLS_KEY "$tls_key"
      log "HTTPS enabled for panel (self-signed cert)"
    fi
  fi

  if [[ "${PANEL_ACCESS:-ip}" == "ssh" ]]; then
    safety_panel_env_set "$env" OLCRTC_PUBLIC_URL "http://127.0.0.1:8888"
  else
    safety_panel_env_set "$env" OLCRTC_PUBLIC_URL ""
  fi

  log "panel.env: panel access=${PANEL_ACCESS:-ip}, listen=${PANEL_LISTEN_ADDR:-0.0.0.0}, tls=${panel_tls}"

  local panel_lang="${OLC_LANG:-ru}"
  [[ "$panel_lang" == en ]] || panel_lang=ru
  safety_panel_env_set "$env" OLC_PANEL_LANG "$panel_lang"
}

run_patches() {
  ensure_ui_build_deps
  if ! BUILD=1 bash "$PATCH_SCRIPT"; then
    log "ERROR: патчи/сборка не удались — см. детали выше"
    return 1
  fi
  ensure_panel_jitsi_tls
}
run_community_lists() { bash "$SCRIPT_DIR/fetch-zapret-community-excludes.sh" 2>/dev/null || true; }
run_restart_manager() { systemctl restart olcrtc-manager; }
run_cleanup_tmp() {
  find /tmp -maxdepth 1 -name 'olcrtc-manager-srv-*.yaml' -delete 2>/dev/null || true
  olc_cleanup_build_caches "agent-bootstrap"
}

if [[ "$REBUILD_ONLY" -eq 1 ]]; then
  run_patches
  run_cleanup_tmp
  run_restart_manager
  exit 0
fi

setup_zapret() {
  [[ "${OLCRTC_ENABLE_ZAPRET:-1}" -eq 1 ]] || return 0
  [[ "$RU_VPS" -eq 1 ]] || return 0
  if [[ "${OLCRTC_ZAPRET_REINSTALL:-0}" != "1" ]] && [[ -x /opt/zapret/nfq/nfqws ]] && pidof nfqws >/dev/null 2>&1; then
    log "zapret: sync excludes from split lists + carriers (set OLCRTC_ZAPRET_REINSTALL=1 for full reinstall)"
    olc_run_quiet_with_progress "zapret sync excludes" "/var/log/olcrtc-zapret-sync.log" \
      bash "$SCRIPT_DIR/zapret-sync-excludes.sh" --reload-zapret \
      || log "WARN: zapret sync failed — см. /var/log/olcrtc-zapret-sync.log"
    return 0
  fi
  log "zapret (direct egress DPI — may take several minutes on first install)"
  bash "$SCRIPT_DIR/tor-bridge-pool.sh" --jobs 8 --target 10 2>/dev/null || true
  systemctl restart tor@default 2>/dev/null || true
  export OLCRTC_ZAPRET_FULL="${OLCRTC_ZAPRET_FULL:-1}"
  olc_run_with_progress "установка/обновление zapret" bash "$SCRIPT_DIR/install-zapret-vps.sh" || log "WARN: zapret install failed — retry manually"
}

# shellcheck source=lib-component-check.sh
if [[ -f "$SCRIPT_DIR/lib-component-check.sh" ]]; then
  source "$SCRIPT_DIR/lib-component-check.sh"
fi

if [[ "$UPDATE" -eq 1 ]]; then
  tui_banner "Обновление Olc-cost-l"
  tui_log_info "Режим: UPDATE — обновление списков, патчей, Tor, zapret, systemd"
  tui_log_info "Можно продолжить с --resume если процесс прервётся"
  tui_divider
  profile_apply_env
  state_step_profile patches              run_patches
  state_step_profile sysctl               setup_sysctl
  state_step_profile warp                 setup_warp
  state_step_profile tor                  setup_tor
  state_step_profile split                setup_split_routing
  state_step_profile fetch-community-lists run_community_lists
  state_step_profile zapret               setup_zapret
  state_step_profile systemd              setup_systemd
  state_step_profile cron                 setup_cron
  state_step_profile cleanup-tmp          run_cleanup_tmp
  state_step_profile restart-manager      run_restart_manager
  profile_apply_runtime_toggles 2>/dev/null || true
  state_finish
  tui_divider
  tui_log_success "✓ Обновление успешно завершено!"
  tui_divider
  olc_print_finish_help 8888
  exit 0
fi

if [[ "$INCREMENTAL" -eq 1 ]]; then
  tui_banner "Доустановка Olc-cost-l"
  tui_log_info "Режим: INCREMENTAL — skip работающих компонентов, доустановка недостающих"
  tui_divider
  profile_apply_env
  
  # Проверка и установка packages только если нужно
  if ! check_packages_installed 2>/dev/null || ! check_binaries_built 2>/dev/null; then
    tui_log_info "Packages/binaries missing - installing"
    state_step packages       install_deps
    state_step patches        run_patches
    state_step webtunnel      build_webtunnel
  else
    tui_log_success "Packages/binaries OK - skip"
  fi
  
  # Остальное через profile (умный skip)
  state_step_profile sysctl               setup_sysctl
  state_step_profile warp                 setup_warp
  state_step_profile tor                  setup_tor
  state_step_profile split                setup_split_routing
  state_step_profile fetch-community-lists run_community_lists
  state_step_profile zapret               setup_zapret
  state_step_profile systemd              setup_systemd
  state_step_profile cron                 setup_cron
  state_step_profile cleanup-tmp          run_cleanup_tmp
  state_step_profile restart-manager      run_restart_manager
  profile_apply_runtime_toggles 2>/dev/null || true
  state_finish
  tui_divider
  tui_log_success "✓ Доустановка успешно завершена!"
  tui_divider
  olc_print_finish_help 8888
  exit 0
fi

if [[ "$FULL" -eq 1 ]]; then
  state_step packages       install_deps
  state_step patches        run_patches
  state_step webtunnel      build_webtunnel
  state_step sysctl         setup_sysctl
else
  if [[ ! -x /usr/local/bin/olcrtc ]] || [[ ! -x /usr/local/bin/olcrtc-manager ]]; then
    log "binaries missing — building patched versions"
    state_step packages       install_deps
    state_step patches        run_patches
    state_step webtunnel      build_webtunnel
  fi
fi

state_step_profile warp                   setup_warp
state_step_profile tor                   setup_tor
state_step_profile split                 setup_split_routing
state_step_profile fetch-community-lists run_community_lists
state_step_profile zapret                setup_zapret
state_step systemd               setup_systemd
state_step cron                  setup_cron
state_step cleanup-tmp           run_cleanup_tmp
state_step start-manager         bash -c 'systemctl enable --now olcrtc-manager.service 2>/dev/null || systemctl restart olcrtc-manager.service'
state_finish

tui_divider
tui_banner "Установка завершена!"
echo ""

tui_log_info "Документация: $DOC"
tui_log_info "Патчи: $REPO_ROOT/patches/PATCHES.md"
if [[ "$ENABLE_TOR" -eq 0 ]]; then
  tui_log_info "Режим: FOREIGN / NO TOR — только панель, без мостов и split"
else
  tui_log_info "Режим: Tor + bridge pool (RU VPS)"
  if [[ "$RU_VPS" -eq 1 && "$ENABLE_SPLIT" -eq 1 ]]; then
    tui_log_info "Split: *.ru + players + RF-blocked → direct (zapret DPI); force-tor (YT) + rest → Tor"
  elif [[ "$ENABLE_SPLIT" -eq 0 ]]; then
    tui_log_info "Split: disabled (--no-split), весь трафик через Tor exit"
  fi
fi
tui_log_info "Olcbox: https://github.com/alananisimov/olcbox/releases"
tui_log_info "Задайте OLCRTC_PUBLIC_URL в panel.env (DDNS, не raw IP)"
olc_print_finish_help 8888
