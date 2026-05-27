#!/usr/bin/env bash
# Ручная проверка места на диске с подсказками на русском.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-disk-preflight.sh
source "$SCRIPT_DIR/lib-disk-preflight.sh"

if olc_preflight_disk_space "ручная проверка (olc-disk-check)"; then
  echo "[olc-disk] OK: места на / и /tmp достаточно для Olc-cost-l."
  df -h / /tmp 2>/dev/null || df -h /
  exit 0
fi
exit 1
