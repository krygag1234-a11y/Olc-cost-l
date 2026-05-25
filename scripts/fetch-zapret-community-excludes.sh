#!/usr/bin/env bash
# Refresh bundled community zapret exclude lists (Flowseal).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${ZAPRET_COMMUNITY_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)/data/zapret-community-excludes}"
BASE='https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/lists'
install -d "$DEST"
curl -fsSL -o "$DEST/flowseal-list-exclude.txt" "$BASE/list-exclude.txt"
curl -fsSL -o "$DEST/flowseal-ipset-exclude.txt" "$BASE/ipset-exclude.txt"
echo "[fetch-zapret-community] $(wc -l <"$DEST/flowseal-list-exclude.txt") domains, $(wc -l <"$DEST/flowseal-ipset-exclude.txt") CIDR lines → $DEST"
