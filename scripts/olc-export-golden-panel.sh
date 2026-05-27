#!/usr/bin/env bash
# Экспорт эталона панели с VPS → packaging/golden-panel/ (для «синк olc»).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GOLDEN_DIR="${OLC_GOLDEN_PANEL_DIR:-$REPO_ROOT/packaging/golden-panel}"
SRC="${OLC_PANEL_SRC:-/tmp/olcrtc-manager-panel}"

log() { echo "[export-golden] $*"; }

[[ -f "$SRC/src/main.tsx" && -f "$SRC/cmd/olcrtc-manager/main.go" ]] || {
  log "ОШИБКА: нет $SRC/src/main.tsx или cmd/olcrtc-manager/main.go"
  exit 1
}

install -d "$GOLDEN_DIR"
cp -f "$SRC/src/main.tsx" "$GOLDEN_DIR/main.tsx"
cp -f "$SRC/cmd/olcrtc-manager/main.go" "$GOLDEN_DIR/main.go"
(
  cd "$GOLDEN_DIR"
  sha256sum main.go main.tsx > SHA256SUMS
)

log "ok: $GOLDEN_DIR (обновите репо: git add packaging/golden-panel && commit)"
