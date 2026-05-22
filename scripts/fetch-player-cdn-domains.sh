#!/usr/bin/env bash
# Merge static RU video balancer domain list (no network).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${RU_PLAYER_DOMAINS:-/var/lib/olcrtc/ru-player-cdn-domains.txt}"
FULL="$REPO_ROOT/data/ru-video-balancers-full.txt"
EMBED="$REPO_ROOT/data/ru-embed-balancers.txt"

{
  echo "# RU player/CDN direct rules — $(date -Iseconds)"
  [[ -f "$FULL" ]] && grep -v '^#' "$FULL" | awk 'NF'
  [[ -f "$EMBED" ]] && grep -v '^#' "$EMBED" | awk 'NF'
} | awk '!seen[$0]++' >"$OUT"
echo "[player-cdn] $(grep -cvE '^#|^$' "$OUT") rules → $OUT"
