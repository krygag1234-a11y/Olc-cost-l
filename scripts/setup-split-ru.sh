#!/usr/bin/env bash
# Split tunnel lists: RU CIDR + CDN/плееры. Только RU VPS (Tor + --full).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "${OLCRTC_RU_VPS:-1}" == "1" ]] || {
  echo "[setup-split-ru] skip: OLCRTC_RU_VPS!=1 (foreign VPS)" >&2
  exit 0
}

echo "[setup-split-ru] RU CIDR (ipgeoinfo)…"
bash "$SCRIPT_DIR/fetch-ru-cidrs.sh"

echo "[setup-split-ru] global CDN…"
bash "$SCRIPT_DIR/fetch-cdn-direct.sh" 2>/dev/null || true

echo "[setup-split-ru] RU player CDN…"
bash "$SCRIPT_DIR/fetch-ru-player-cdn.sh"

echo "[setup-split-ru] merge direct-all.txt…"
bash "$SCRIPT_DIR/merge-direct-cidrs.sh"

ENV_FILE="${PANEL_ENV:-/etc/olcrtc-manager/panel.env}"
if [[ -f /var/lib/olcrtc/direct-all.txt ]]; then
  mkdir -p "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"
  if grep -q '^OLCRTC_DIRECT_CIDRS=' "$ENV_FILE" 2>/dev/null; then
    sed -i 's|^OLCRTC_DIRECT_CIDRS=.*|OLCRTC_DIRECT_CIDRS=/var/lib/olcrtc/direct-all.txt|' "$ENV_FILE"
  else
    echo 'OLCRTC_DIRECT_CIDRS=/var/lib/olcrtc/direct-all.txt' >>"$ENV_FILE"
  fi
fi
echo "[setup-split-ru] done ($(wc -l < /var/lib/olcrtc/direct-all.txt) routes)"
