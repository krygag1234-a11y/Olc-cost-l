#!/usr/bin/env bash
# Install/uninstall optional stack components (background job from panel).
# Usage: olc-component-job.sh <zapret|tor|split|bridges> <install|uninstall> [job_id]
set -euo pipefail

COMPONENT="${1:?component}"
ACTION="${2:?install|uninstall}"
JOB_ID="${3:-component-${COMPONENT}-$(date -u +%Y%m%dT%H%M%SZ)}"
REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/var/log/olcrtc-component-${COMPONENT}-${ACTION}.log"
JOBS_DIR=/var/lib/olcrtc/panel-jobs
STATUS="$JOBS_DIR/${JOB_ID}.json"

install -d "$JOBS_DIR" /var/log

write_status() {
  local st="$1" ec="${2:-0}" err="${3:-}"
  jq -n \
    --arg id "$JOB_ID" \
    --arg component "$COMPONENT" \
    --arg action "$ACTION" \
    --arg status "$st" \
    --argjson exit_code "$ec" \
    --arg error "$err" \
    --arg log "$LOG" \
    '{job_id:$id, type:"component", component:$component, action:$action, status:$status, exit_code:$exit_code, error:$error, log_path:$log}' \
    >"$STATUS"
}

write_status running 0 ""

run_install() {
  case "$COMPONENT" in
    zapret)
      if [[ -x /opt/zapret/nfq/nfqws ]] && pidof nfqws >/dev/null 2>&1; then
        bash "$SCRIPT_DIR/zapret-sync-excludes.sh" --reload-zapret
      else
        OLCRTC_ZAPRET_REINSTALL=1 bash "$SCRIPT_DIR/install-zapret-vps.sh"
      fi
      bash "$SCRIPT_DIR/olc-feature.sh" zapret on
      ;;
    tor)
      bash "$SCRIPT_DIR/install-tor-pluggable-transports.sh" 2>/dev/null || true
      bash "$SCRIPT_DIR/configure-tor-exit.sh" 2>/dev/null || true
      bash "$SCRIPT_DIR/olc-feature.sh" tor on
      ;;
    split)
      bash "$SCRIPT_DIR/setup-split-ru.sh"
      bash "$SCRIPT_DIR/olc-feature.sh" split on
      ;;
    bridges)
      bash "$SCRIPT_DIR/install-tor-pluggable-transports.sh"
      bash "$SCRIPT_DIR/tor-bridge-pool.sh" refresh 2>/dev/null || true
      bash "$SCRIPT_DIR/olc-feature.sh" webtunnel on 2>/dev/null || true
      ;;
    *) echo "unknown component: $COMPONENT" >&2; return 1 ;;
  esac
}

run_uninstall() {
  case "$COMPONENT" in
    zapret) bash "$SCRIPT_DIR/olc-feature.sh" zapret off ;;
    tor)
      bash "$SCRIPT_DIR/olc-feature.sh" tor off
      bash "$SCRIPT_DIR/olc-feature.sh" split off
      ;;
    split) bash "$SCRIPT_DIR/olc-feature.sh" split off ;;
    bridges) bash "$SCRIPT_DIR/olc-feature.sh" webtunnel off ;;
    *) echo "unknown component: $COMPONENT" >&2; return 1 ;;
  esac
}

{
  echo "=== $COMPONENT $ACTION $JOB_ID $(date -u -Iseconds) ==="
  case "$ACTION" in
    install) run_install ;;
    uninstall) run_uninstall ;;
    *) echo "bad action: $ACTION" >&2; exit 1 ;;
  esac
  echo "=== done ==="
} >>"$LOG" 2>&1 && write_status done 0 "" || write_status failed "$?" "see $LOG"
