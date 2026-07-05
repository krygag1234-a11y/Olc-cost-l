#!/usr/bin/env bash
# Патчит packaging/golden-panel/main.tsx добавляя UI для randomization
# Вызывается ДО apply-golden-panel.sh чтобы эталон уже содержал UI изменения
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GOLDEN_TSX="${REPO_ROOT}/packaging/golden-panel/main.tsx"

[[ -f "$GOLDEN_TSX" ]] || {
  echo "[patch-golden-panel-randomization-ui] ERROR: $GOLDEN_TSX not found"
  exit 1
}

# Apply randomization-ui-full patch to golden panel
bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-randomization-ui-full.sh" "$GOLDEN_TSX"

# Apply selective-randomization-ui patch to golden panel
bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-selective-randomization-ui.sh" "$GOLDEN_TSX"

echo "[patch-golden-panel-randomization-ui] done"
