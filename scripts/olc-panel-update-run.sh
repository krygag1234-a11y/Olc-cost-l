#!/usr/bin/env bash
# Background panel update (git pull + patches + manager restart). Started by manager API.
set -euo pipefail

REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-git-safe.sh
source "$SCRIPT_DIR/lib-git-safe.sh"
JOB_ID="${1:-update-$(date -u +%Y%m%dT%H%M%SZ)}"
LOCK=/var/lib/olcrtc/panel-update.lock
STATUS=/var/lib/olcrtc/panel-update-status.json
LOG=/var/log/olcrtc-panel-update.log
JOBS_DIR=/var/lib/olcrtc/panel-jobs

install -d /var/lib/olcrtc "$JOBS_DIR"
echo "$$" >"$LOCK"

write_status() {
  local st="$1" ec="${2:-0}" err="${3:-}"
  jq -n \
    --arg id "$JOB_ID" \
    --arg status "$st" \
    --argjson exit_code "$ec" \
    --arg error "$err" \
    --arg log "$LOG" \
    --arg started "$(date -u -Iseconds)" \
    '{job_id:$id, type:"update", status:$status, exit_code:$exit_code, error:$error, log_path:$log, started_at:$started}' \
    >"$STATUS"
  cp -f "$STATUS" "$JOBS_DIR/${JOB_ID}.json"
}

cleanup() {
  rm -f "$LOCK"
}
trap cleanup EXIT

write_status running 0 ""
{
  echo "=== panel update $JOB_ID $(date -u -Iseconds) ==="
  olc_git_safe_register "$REPO_ROOT"
  olc_git "$REPO_ROOT" fetch origin main --depth 1 2>/dev/null || olc_git "$REPO_ROOT" fetch origin main
  olc_git "$REPO_ROOT" pull --ff-only origin main
  BUILD=1 bash scripts/apply-olcrtc-patches.sh
  systemctl restart olcrtc-manager
  echo "=== done $(date -u -Iseconds) ==="
} >>"$LOG" 2>&1 && write_status done 0 "" || write_status failed "$?" "update failed — see $LOG"
