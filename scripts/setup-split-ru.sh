#!/usr/bin/env bash
# Split tunnel RU VPS: geoip RU + domain rules (без CDN /32 — иначе 404 nginx).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "${OLCRTC_RU_VPS:-1}" == "1" ]] || {
  echo "[setup-split-ru] skip: OLCRTC_RU_VPS!=1 (foreign VPS)" >&2
  exit 0
}

echo "[setup-split-ru] RU CIDR (geoip)…"
bash "$SCRIPT_DIR/fetch-ru-cidrs.sh"

echo "[setup-split-ru] RU direct domains (players/CDN by hostname)…"
bash "$SCRIPT_DIR/fetch-ru-direct-domains.sh"

# Legacy IP CDN lists — optional, off by default (causes 404 on wrong nginx edge)
if [[ "${OLCRTC_INCLUDE_CDN_IPS:-0}" == "1" ]]; then
  echo "[setup-split-ru] WARN: including CDN /32 lists (may cause 404 nginx)…"
  bash "$SCRIPT_DIR/fetch-cdn-direct.sh" 2>/dev/null || true
  bash "$SCRIPT_DIR/fetch-ru-player-cdn.sh" 2>/dev/null || true
  OUT=/var/lib/olcrtc/direct-all.txt \
    CDN=/var/lib/olcrtc/cdn-direct.txt \
    RU_PLAYER=/var/lib/olcrtc/ru-player-cdn.txt \
    bash "$SCRIPT_DIR/merge-direct-cidrs.sh"
  DIRECT_CIDRS=/var/lib/olcrtc/direct-all.txt
else
  DIRECT_CIDRS=/var/lib/olcrtc/ru-cidrs.txt
  echo "[setup-split-ru] CIDR only: $DIRECT_CIDRS (no CDN /32)"
fi

ENV_FILE="${PANEL_ENV:-/etc/olcrtc-manager/panel.env}"
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"

set_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >>"$ENV_FILE"
  fi
}

set_env OLCRTC_DIRECT_CIDRS "$DIRECT_CIDRS"
set_env OLCRTC_DIRECT_DOMAINS /var/lib/olcrtc/ru-direct-domains.txt

echo "[setup-split-ru] done: CIDR=$(wc -l <"$DIRECT_CIDRS") domains=$(grep -cE '^[.]' /var/lib/olcrtc/ru-direct-domains.txt)"
