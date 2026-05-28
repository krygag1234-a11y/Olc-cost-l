#!/usr/bin/env bash
# Install/uninstall optional stack components (background job from panel).
# Usage: olc-component-job.sh <zapret|tor|split|bridges|warp> <install|uninstall> [job_id]
set -euo pipefail

COMPONENT="${1:?component}"
ACTION="${2:?install|uninstall}"
JOB_ID="${3:-component-${COMPONENT}-$(date -u +%Y%m%dT%H%M%SZ)}"
REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-disk-preflight.sh
source "$SCRIPT_DIR/lib-disk-preflight.sh"
# shellcheck source=lib-vps-backup.sh
source "$SCRIPT_DIR/lib-vps-backup.sh"
olc_preflight_disk_space "component-${COMPONENT}-${ACTION}" || exit 1
olc_preflight_vps_backup "component-${COMPONENT}-${ACTION}" || true
LOG="/var/log/olcrtc-component-${COMPONENT}-${ACTION}.log"
JOBS_DIR=/var/lib/olcrtc/panel-jobs
STATUS="$JOBS_DIR/${JOB_ID}.json"

install -d "$JOBS_DIR" /var/log

write_status() {
  local st="$1" ec="${2:-0}" err="${3:-}"
  local now
  now="$(date -u -Iseconds)"
  if [[ "$st" == "running" ]]; then
    jq -n \
      --arg id "$JOB_ID" \
      --arg component "$COMPONENT" \
      --arg action "$ACTION" \
      --arg status "$st" \
      --argjson exit_code "$ec" \
      --arg error "$err" \
      --arg log "$LOG" \
      --arg started_at "$now" \
      '{job_id:$id, type:"component", component:$component, action:$action, status:$status, exit_code:$exit_code, error:$error, log_path:$log, started_at:$started_at}' \
      >"$STATUS"
  else
    jq -n \
      --arg id "$JOB_ID" \
      --arg component "$COMPONENT" \
      --arg action "$ACTION" \
      --arg status "$st" \
      --argjson exit_code "$ec" \
      --arg error "$err" \
      --arg log "$LOG" \
      --arg finished_at "$now" \
      '{job_id:$id, type:"component", component:$component, action:$action, status:$status, exit_code:$exit_code, error:$error, log_path:$log, finished_at:$finished_at}' \
      >"$STATUS"
  fi
}

write_status running 0 ""

finalize_job() {
  local ec=$?
  if [[ ! -f "$STATUS" ]]; then
    return "$ec"
  fi
  local cur
  cur="$(jq -r '.status // ""' "$STATUS" 2>/dev/null || echo "")"
  if [[ "$cur" != "running" ]]; then
    return "$ec"
  fi
  if (( ec == 0 )); then
    write_status done 0 ""
  else
    write_status failed "$ec" "job exited with status $ec (see $LOG)"
  fi
  return "$ec"
}
trap finalize_job EXIT

run_install() {
  rm -f "/var/lib/olcrtc/component-removed/$COMPONENT" 2>/dev/null || true
  case "$COMPONENT" in
    zapret)
      if [[ -x /opt/zapret/nfq/nfqws ]] && pidof nfqws >/dev/null 2>&1; then
        bash "$SCRIPT_DIR/zapret-sync-excludes.sh" --reload-zapret
      elif [[ -x /opt/zapret/nfq/nfqws ]]; then
        bash "$SCRIPT_DIR/install-zapret-vps.sh" || OLCRTC_ZAPRET_REINSTALL=1 bash "$SCRIPT_DIR/install-zapret-vps.sh"
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
      # Split routes non-RU traffic through Tor. If the UI asks to install split
      # while Tor is disabled, enable the dependency first instead of failing late.
      bash "$SCRIPT_DIR/install-tor-pluggable-transports.sh" 2>/dev/null || true
      bash "$SCRIPT_DIR/configure-tor-exit.sh" 2>/dev/null || true
      bash "$SCRIPT_DIR/olc-feature.sh" tor on
      bash "$SCRIPT_DIR/setup-split-ru.sh"
      bash "$SCRIPT_DIR/olc-feature.sh" split on
      ;;
    bridges)
      bash "$SCRIPT_DIR/install-tor-pluggable-transports.sh"
      bash "$SCRIPT_DIR/tor-bridge-pool.sh" refresh 2>/dev/null || true
      bash "$SCRIPT_DIR/olc-feature.sh" webtunnel on 2>/dev/null || true
      ;;
    warp)
      bash "$SCRIPT_DIR/install-warp.sh"
      bash "$SCRIPT_DIR/olc-feature.sh" warp on
      ;;
    *) echo "unknown component: $COMPONENT" >&2; return 1 ;;
  esac
}

run_uninstall() {
  bash "$SCRIPT_DIR/olc-component-remove.sh" "$COMPONENT"
}

{
  echo "=== $COMPONENT $ACTION $JOB_ID $(date -u -Iseconds) ==="
  case "$ACTION" in
    install) run_install ;;
    uninstall) run_uninstall ;;
    *) echo "bad action: $ACTION" >&2; exit 1 ;;
  esac
  echo "=== done ==="
} >>"$LOG" 2>&1
job_ec=$?
# install scripts may exit 1 after successful work (e.g. zapret tmp trap); trust log marker.
if grep -qF "=== done ===" "$LOG" 2>/dev/null; then
  write_status done 0 ""
  job_ec=0
elif (( job_ec == 0 )); then
  write_status done 0 ""
else
  write_status failed "$job_ec" "see $LOG"
fi
if (( job_ec == 0 )) && [[ -x "$SCRIPT_DIR/lib-deploy-profile.sh" ]]; then
  # shellcheck source=lib-deploy-profile.sh
  source "$SCRIPT_DIR/lib-deploy-profile.sh"
  export OLC_REPO_ROOT="$REPO_ROOT"
  profile_after_component_job "$COMPONENT" "$ACTION" || true
fi
