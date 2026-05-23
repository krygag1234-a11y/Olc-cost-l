#!/usr/bin/env bash
# Global domains → always Tor (override direct geosite/CDN rules).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${FORCE_TOR_DOMAINS:-/var/lib/olcrtc/force-tor-domains.txt}"
SEED="${FORCE_TOR_SEED:-$REPO_ROOT/data/global-force-tor-domains.txt}"
safety_check_output_path OUT "$OUT"

{
  echo "# Force Tor — $(date -Iseconds)"
  [[ -f "$SEED" ]] && grep -v '^#' "$SEED" | awk 'NF'
} | awk '!seen[$0]++' >"$OUT"
echo "[force-tor] $(grep -cvE '^#|^$' "$OUT") rules → $OUT"
