#!/usr/bin/env bash
# Split tunnel RU VPS: geoip RU + domain rules (без CDN /32 — иначе 404 nginx).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

[[ "${OLCRTC_RU_VPS:-1}" == "1" ]] || {
  echo "[setup-split-ru] skip: OLCRTC_RU_VPS!=1 (foreign VPS)" >&2
  exit 0
}

echo "[setup-split-ru] RU CIDR (geoip)…"
bash "$SCRIPT_DIR/fetch-ru-cidrs.sh"

REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
EXTRA_DST="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
SEED="$REPO_ROOT/data/ru-domains-extra.txt"
if [[ -f "$SEED" ]]; then
  install -d "$(dirname "$EXTRA_DST")"
  install -m 0644 "$SEED" "$EXTRA_DST"
  echo "[setup-split-ru] seeded $EXTRA_DST from repo"
fi

echo "[setup-split-ru] geosite RU domains (~10k from GrimbirdUsers) + builtins…"
bash "$SCRIPT_DIR/fetch-force-tor-domains.sh"
bash "$SCRIPT_DIR/fetch-ru-direct-domains.sh"
bash "$SCRIPT_DIR/fetch-ru-blocked-tor-domains.sh"

# Legacy IP CDN lists — optional, off by default (causes 404 on wrong nginx edge)
if [[ "${OLCRTC_SPLIT_CIDR_ONLY:-0}" == "1" ]]; then
  OLCRTC_INCLUDE_CDN_IPS=0
fi
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
safety_check_output_path ENV_FILE "$ENV_FILE"
safety_check_output_path DIRECT_CIDRS "$DIRECT_CIDRS"

safety_panel_env_set "$ENV_FILE" OLCRTC_DIRECT_CIDRS "$DIRECT_CIDRS"
safety_panel_env_set "$ENV_FILE" OLCRTC_DIRECT_DOMAINS /var/lib/olcrtc/ru-direct-domains.txt
safety_panel_env_set "$ENV_FILE" OLCRTC_BLOCKED_TOR_DOMAINS /var/lib/olcrtc/ru-blocked-tor-domains.txt
safety_panel_env_set "$ENV_FILE" OLCRTC_FORCE_TOR_DOMAINS /var/lib/olcrtc/force-tor-domains.txt

# Panel hints (idempotent refresh)
grep -q '^# Olc-cost-l split' "$ENV_FILE" 2>/dev/null || cat >>"$ENV_FILE" <<EOF

# Olc-cost-l split — обновление списков:
#   ${SCRIPT_DIR}/setup-split-ru.sh
#   ${SCRIPT_DIR}/fetch-ru-cidrs.sh
#   ${SCRIPT_DIR}/fetch-ru-direct-domains.sh
#   ${SCRIPT_DIR}/fetch-ru-blocked-tor-domains.sh
EOF
sed -i 's|^# RU IP → direct.*|# Olc-cost-l split (см. setup-split-ru.sh в репо)|' "$ENV_FILE" 2>/dev/null || true

dom_n="$(grep -cvE '^#|^$' /var/lib/olcrtc/ru-direct-domains.txt 2>/dev/null || echo 0)"
echo "[setup-split-ru] done: CIDR=$(wc -l <"$DIRECT_CIDRS") domains=${dom_n} (+ builtin *.ru in olcrtc)"

if [[ -x /opt/zapret/nfq/nfqws ]] && [[ "${OLCRTC_ENABLE_ZAPRET:-1}" == "1" ]]; then
  bash "$SCRIPT_DIR/zapret-sync-excludes.sh" --reload-zapret 2>/dev/null || true
fi
