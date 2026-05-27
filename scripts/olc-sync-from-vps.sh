#!/usr/bin/env bash
# Полный «синк olc»: тестовый VPS → репозиторий Olc-cost-l (без деплоя на VPS).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SSH_KEY="${OLC_SYNC_SSH_KEY:-/root/.ssh/yandex_bm_test_key}"
SSH_HOST="${OLC_SYNC_HOST:-kryga@89.169.186.195}"
REMOTE_PANEL="${OLC_REMOTE_PANEL:-/tmp/olcrtc-manager-panel}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Использование: olc-sync-from-vps.sh [опции]

  Синхронизирует рабочее состояние тестового VPS в репозиторий:
    - packaging/golden-panel (main.tsx, main.go, SHA256SUMS)
    - packaging/vps-snapshot/ (features.env, panel.env без секретов, units list)

  Опции:
    --host USER@IP     SSH хост (по умолчанию kryga@89.169.186.195)
    --key PATH         SSH ключ
    --dry-run          только показать, что будет скопировано
    -h, --help

  После скрипта: git add, git commit, git push (вручную или попроси агента).

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) SSH_HOST="$2"; shift 2 ;;
    --key) SSH_KEY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Неизвестный аргумент: $1" >&2; usage; exit 1 ;;
  esac
done

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15)
SNAP_DIR="$REPO_ROOT/packaging/vps-snapshot"
GOLDEN_DIR="$REPO_ROOT/packaging/golden-panel"

log() { echo "[olc-sync] $*"; }

remote() {
  ssh "${SSH_OPTS[@]}" "$SSH_HOST" "$@"
}

scp_from() {
  scp "${SSH_OPTS[@]}" "$SSH_HOST:$1" "$2"
}

log "хост: $SSH_HOST"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run: golden-panel + vps-snapshot"
  exit 0
fi

install -d "$GOLDEN_DIR" "$SNAP_DIR"

# 1) Golden panel
scp_from "$REMOTE_PANEL/src/main.tsx" "$GOLDEN_DIR/main.tsx"
scp_from "$REMOTE_PANEL/cmd/olcrtc-manager/main.go" "$GOLDEN_DIR/main.go"
(
  cd "$GOLDEN_DIR"
  sha256sum main.go main.tsx > SHA256SUMS
)
log "golden-panel обновлён"

# 2) VPS snapshot (без паролей)
remote "cat /var/lib/olcrtc/features.env 2>/dev/null || true" >"$SNAP_DIR/features.env" || true
remote "grep -vE 'PASS|SECRET|TOKEN' /etc/olcrtc-manager/panel.env 2>/dev/null || true" >"$SNAP_DIR/panel.env.example" || true
remote "systemctl list-unit-files 'olcrtc-*' --no-pager 2>/dev/null | head -40" >"$SNAP_DIR/systemd-units.txt" || true
remote "cd /opt/Olc-cost-l && git log -1 --oneline 2>/dev/null" >"$SNAP_DIR/olc-cost-l-commit.txt" || true
date -u +"%Y-%m-%dT%H:%M:%SZ" >"$SNAP_DIR/exported-at.txt"

# 3) Verify
export OLC_REPO_ROOT="$REPO_ROOT"
export OLCRTC_MGR_REPO="$REMOTE_PANEL"
if [[ -d "$REMOTE_PANEL/src" ]]; then
  bash "$SCRIPT_DIR/olc-panel-verify.sh" || log "WARN: verify на локальной копии panel — запустите после apply на VPS"
else
  log "локально $REMOTE_PANEL нет — verify пропущен"
fi

log "готово. Дальше:"
echo "  cd $REPO_ROOT"
echo "  git add packaging/golden-panel packaging/vps-snapshot"
echo "  git status"
echo "  git commit -m 'sync: golden panel + VPS snapshot from test host'"
