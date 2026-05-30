#!/usr/bin/env bash
# Split tunnel RU VPS: geoip RU + domain rules (без CDN /32 — иначе 404 nginx).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-output.sh
source "$SCRIPT_DIR/lib-output.sh"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

[[ "${OLCRTC_RU_VPS:-1}" == "1" ]] || {
  olc_print_info "Пропуск: OLCRTC_RU_VPS!=1 (зарубежный VPS)"
  exit 0
}

olc_print_header "Настройка Split Routing для RU VPS"

olc_print_section "Загрузка RU CIDR (geoip)"
if [[ "${1:-}" == "--quick" ]] || [[ "${OLCRTC_SPLIT_QUICK:-0}" == "1" ]]; then
  olc_print_info "Быстрый режим: пропуск тяжёлых upstream запросов"
  export OLCRTC_SKIP_GEOSITE_FETCH=1
  export OLCRTC_SKIP_BLOCKED_TOR_FETCH=1
  if [[ -s /var/lib/olcrtc/ru-cidrs.txt ]]; then
    olc_print_info "Пропуск fetch-ru-cidrs (файл существует)"
  else
    bash "$SCRIPT_DIR/fetch-ru-cidrs.sh"
  fi
else
  bash "$SCRIPT_DIR/fetch-ru-cidrs.sh"
fi

REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
EXTRA_DST="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
SEED="$REPO_ROOT/data/ru-domains-extra.txt"
if [[ -f "$SEED" ]]; then
  install -d "$(dirname "$EXTRA_DST")"
  install -m 0644 "$SEED" "$EXTRA_DST"
  olc_print_ok "Seed файл скопирован: $EXTRA_DST"
fi

olc_print_section "Загрузка списков доменов"
olc_print_step "Geosite RU domains (~10k от GrimbirdUsers)"
bash "$SCRIPT_DIR/fetch-force-tor-domains.sh"
bash "$SCRIPT_DIR/fetch-ru-direct-domains.sh"
bash "$SCRIPT_DIR/fetch-ru-blocked-tor-domains.sh"

# Legacy IP CDN lists — optional, off by default (causes 404 on wrong nginx edge)
if [[ "${OLCRTC_SPLIT_CIDR_ONLY:-0}" == "1" ]]; then
  OLCRTC_INCLUDE_CDN_IPS=0
fi
if [[ "${OLCRTC_INCLUDE_CDN_IPS:-0}" == "1" ]]; then
  olc_print_warn "Включение CDN /32 списков (может вызвать 404 nginx)"
  bash "$SCRIPT_DIR/fetch-cdn-direct.sh" 2>/dev/null || true
  bash "$SCRIPT_DIR/fetch-ru-player-cdn.sh" 2>/dev/null || true
  OUT=/var/lib/olcrtc/direct-all.txt \
    CDN=/var/lib/olcrtc/cdn-direct.txt \
    RU_PLAYER=/var/lib/olcrtc/ru-player-cdn.txt \
    bash "$SCRIPT_DIR/merge-direct-cidrs.sh"
  DIRECT_CIDRS=/var/lib/olcrtc/direct-all.txt
else
  DIRECT_CIDRS=/var/lib/olcrtc/ru-cidrs.txt
  olc_print_info "Только CIDR: $DIRECT_CIDRS (без CDN /32)"
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
install -d /var/lib/olcrtc/lists
if [[ -x "$SCRIPT_DIR/olc-split-analyze.sh" ]]; then
  if [[ -f /etc/olcrtc-manager/config.json ]]; then
    bash "$SCRIPT_DIR/olc-split-analyze.sh" sync-config /etc/olcrtc-manager/config.json >/dev/null 2>&1 || true
  else
    bash "$SCRIPT_DIR/olc-split-analyze.sh" rebuild >/dev/null 2>&1 || true
  fi
  dom_n="$(grep -cvE '^#|^$' /var/lib/olcrtc/ru-direct-domains.txt 2>/dev/null || echo 0)"
fi

olc_print_section "Результат"
olc_print_key_value "CIDR записей" "$(wc -l <"$DIRECT_CIDRS")"
olc_print_key_value "Доменов" "${dom_n} (+ встроенные *.ru в olcrtc)"

if [[ -x /opt/zapret/nfq/nfqws ]] && [[ "${OLCRTC_ENABLE_ZAPRET:-1}" == "1" ]]; then
  olc_print_step "Синхронизация zapret excludes"
  bash "$SCRIPT_DIR/zapret-sync-excludes.sh" --reload-zapret 2>/dev/null || true
fi

olc_print_ok "Split routing настроен"
