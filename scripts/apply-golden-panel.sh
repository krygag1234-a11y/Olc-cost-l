#!/usr/bin/env bash
# Копирует эталон панели с рабочего тестового VPS (packaging/golden-panel/).
# Вызывается в конце apply-olcrtc-patches.sh — выравнивает UI/Go с эталоном.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GOLDEN_DIR="${OLC_GOLDEN_PANEL_DIR:-$REPO_ROOT/packaging/golden-panel}"
MGR_REPO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}}"

log() { echo "[golden-panel] $*"; }

[[ -f "$GOLDEN_DIR/main.tsx" && -f "$GOLDEN_DIR/main.go" ]] || {
  log "ОШИБКА: нет $GOLDEN_DIR/main.tsx или main.go — обновите эталон с тестового VPS"
  exit 1
}

if [[ -f "$GOLDEN_DIR/SHA256SUMS" ]]; then
  (cd "$GOLDEN_DIR" && sha256sum -c SHA256SUMS) || {
    log "ОШИБКА: checksum эталона не совпадает"
    exit 1
  }
fi

[[ -d "$MGR_REPO/src" ]] || { log "ОШИБКА: нет $MGR_REPO/src"; exit 1; }
install -d "$MGR_REPO/cmd/olcrtc-manager"

cp -f "$GOLDEN_DIR/main.tsx" "$MGR_REPO/src/main.tsx"
cp -f "$GOLDEN_DIR/main.go" "$MGR_REPO/cmd/olcrtc-manager/main.go"
chmod 644 "$MGR_REPO/src/main.tsx" "$MGR_REPO/cmd/olcrtc-manager/main.go"

log "ok: main.tsx + main.go ← $GOLDEN_DIR (эталон тестового VPS)"
