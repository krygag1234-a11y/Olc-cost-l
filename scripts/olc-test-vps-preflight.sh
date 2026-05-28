#!/usr/bin/env bash
# Сверка тестового VPS с эталоном репозитория (без деплоя).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GOLDEN_DIR="$REPO_ROOT/packaging/golden-panel"
SSH_KEY="${OLC_SYNC_SSH_KEY:-~/.ssh/test_vps_key}"
SSH_HOST="${OLC_SYNC_HOST:-user@test-vps-ip}"
REMOTE_PANEL="${OLC_REMOTE_PANEL:-/tmp/olcrtc-manager-panel}"

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15)
fail=0

log() { echo "[preflight] $*"; }

remote() { ssh "${SSH_OPTS[@]}" "$SSH_HOST" "$@"; }

[[ -f "$GOLDEN_DIR/main.tsx" && -f "$GOLDEN_DIR/main.go" ]] || {
  log "FAIL: нет golden-panel"
  exit 1
}

if (cd "$GOLDEN_DIR" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
  log "golden SHA256: ok"
else
  log "WARN: golden SHA256 не совпал"
  fail=1
fi

cmp_remote() {
  local name="$1" remote_path="$2"
  local tmp
  tmp="$(mktemp)"
  if scp "${SSH_OPTS[@]}" "$SSH_HOST:$remote_path" "$tmp" 2>/dev/null && cmp -s "$GOLDEN_DIR/$name" "$tmp"; then
    log "$name: тест VPS = эталон репо"
  else
    log "$name: ОТЛИЧАЕТСЯ или не скачан"
    fail=1
  fi
  rm -f "$tmp"
}

cmp_remote main.tsx "$REMOTE_PANEL/src/main.tsx"
cmp_remote main.go "$REMOTE_PANEL/cmd/olcrtc-manager/main.go"

bundle="$(remote "strings /usr/local/bin/olcrtc-manager 2>/dev/null | grep -oE 'index-[A-Za-z0-9_-]+\\.js' | head -1" || true)"
log "bundle: ${bundle:-unknown}"
log "olcrtc-manager: $(remote 'systemctl is-active olcrtc-manager 2>/dev/null' || echo '?')"

if [[ "$fail" -eq 0 ]]; then
  log "OK"
  exit 0
fi
log "FAIL — синхронизируйте: olc-sync-from-vps.sh или scp golden на тест"
exit 1
