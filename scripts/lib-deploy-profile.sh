#!/usr/bin/env bash
# Deploy profile: records which stack components this VPS uses (tor/split/zapret/bridges).
# Read on olc-update so foreign/minimal hosts skip heavy steps.
#
# File: /etc/olcrtc-manager/deploy-profile.json
# Templates: $REPO_ROOT/data/deploy-profiles/*.json
#
# shellcheck shell=bash

: "${OLCRTC_DEPLOY_PROFILE:=/etc/olcrtc-manager/deploy-profile.json}"
: "${OLCRTC_PROFILES_DIR:=${OLC_REPO_ROOT:-}/data/deploy-profiles}"

profile_log() { echo "[profile] $*"; }

profile_ensure_dir() {
  mkdir -p "$(dirname "$OLCRTC_DEPLOY_PROFILE")"
}

profile_from_flags() {
  # Sets: PROFILE_ID PROFILE_LABEL and writes JSON from current shell flags.
  local tor="${1:-${ENABLE_TOR:-1}}"
  local split="${2:-${ENABLE_SPLIT:-1}}"
  local zapret="${3:-${OLCRTC_ENABLE_ZAPRET:-1}}"
  local bridges="${4:-1}"
  local ru="${5:-${RU_VPS:-1}}"
  local fingerprint="${6:-}"
  local warp="${7:-${ENABLE_WARP:-0}}"
  local panel_access="${8:-${PANEL_ACCESS:-ip}}"
  local panel_tls="${9:-${PANEL_TLS:-0}}"
  local panel_listen_addr="0.0.0.0"
  [[ "$panel_access" == "ssh" ]] && panel_listen_addr="127.0.0.1" || panel_access="ip"

  if [[ "$warp" -eq 1 ]]; then
    PROFILE_ID="foreign-warp"
    PROFILE_LABEL="Зарубежный VPS: OlcRTC + WARP (без Tor)"
    tor=0
    split=0
    zapret=0
    bridges=0
    ru=0
  elif [[ "$tor" -eq 0 ]]; then
    PROFILE_ID="foreign-minimal"
    PROFILE_LABEL="Зарубежный VPS: только olcrtc + панель"
    zapret=0
    split=0
    bridges=0
    ru=0
  elif [[ "$zapret" -eq 0 ]]; then
    PROFILE_ID="ru-no-zapret"
    PROFILE_LABEL="RU VPS: Tor + Split + Мосты (без Zapret)"
  elif [[ "$split" -eq 0 ]]; then
    PROFILE_ID="foreign-tor"
    PROFILE_LABEL="Tor-only: без split/zapret"
    zapret=0
    ru=0
  else
    PROFILE_ID="ru-full"
    PROFILE_LABEL="RU VPS: Tor + Split + Zapret + Мосты"
  fi

  if [[ -z "$fingerprint" ]]; then
    fingerprint="agent-bootstrap"
  fi

  profile_ensure_dir
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg id "$PROFILE_ID" \
      --arg label "$PROFILE_LABEL" \
      --arg fp "$fingerprint" \
      --arg panel_access "$panel_access" \
      --arg panel_listen_addr "$panel_listen_addr" \
      --argjson panel_tls "$([[ "$panel_tls" -eq 1 ]] && echo true || echo false)" \
      --argjson tor "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
      --argjson split "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
      --argjson zapret "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
      --argjson bridges "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
      --argjson warp "$([[ "$warp" -eq 1 ]] && echo true || echo false)" \
      --argjson ru "$([[ "$ru" -eq 1 ]] && echo true || echo false)" \
      '{
        schema: 1,
        profile_id: $id,
        label: $label,
        components: { tor: $tor, split: $split, zapret: $zapret, bridges: $bridges, warp: $warp },
        panel: { access: $panel_access, listen_addr: $panel_listen_addr, tls: $panel_tls },
        ru_vps: $ru,
        update_mode: "incremental",
        created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        install_script_fingerprint: $fp
      }' >"$OLCRTC_DEPLOY_PROFILE"
  else
    printf '{"schema":1,"profile_id":"%s","label":"%s","components":{"tor":%s,"split":%s,"zapret":%s,"bridges":%s,"warp":%s},"panel":{"access":"%s","listen_addr":"%s","tls":%s}}\n' \
      "$PROFILE_ID" "$PROFILE_LABEL" \
      "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$warp" -eq 1 ]] && echo true || echo false)" \
      "$panel_access" "$panel_listen_addr" \
      "$([[ "$panel_tls" -eq 1 ]] && echo true || echo false)" \
      >"$OLCRTC_DEPLOY_PROFILE"
  fi
  profile_log "saved $PROFILE_ID → $OLCRTC_DEPLOY_PROFILE"
}

profile_set_panel_access() {
  local access="${1:-ip}"
  local listen_addr="0.0.0.0"
  [[ "$access" == "ssh" ]] && listen_addr="127.0.0.1" || access="ip"
  profile_ensure_dir
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || profile_from_flags
  command -v jq >/dev/null 2>&1 || return 0
  local tmp
  tmp="$(mktemp)"
  jq --arg access "$access" --arg listen "$listen_addr" \
    '.panel.access = $access | .panel.listen_addr = $listen | .updated_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
    "$OLCRTC_DEPLOY_PROFILE" >"$tmp" && mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  profile_log "panel access=$access listen=$listen_addr"
}

profile_panel_access() {
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || { echo "${PANEL_ACCESS:-ip}"; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r '.panel.access // "ip"' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo "ip"
  else
    grep -q '"access":"ssh"' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null && echo ssh || echo ip
  fi
}

profile_panel_listen_addr() {
  local access
  access="$(profile_panel_access)"
  [[ "$access" == "ssh" ]] && echo "127.0.0.1" || echo "0.0.0.0"
}

profile_install_template() {
  local id="$1"
  local tpl="${OLCRTC_PROFILES_DIR}/${id}.json"
  if [[ ! -f "$tpl" ]]; then
    profile_log "template not found: $tpl"
    return 1
  fi
  profile_ensure_dir
  install -m 0644 "$tpl" "$OLCRTC_DEPLOY_PROFILE"
  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    jq --arg t "$(date -u +%FT%TZ)" '.created_at = $t' "$OLCRTC_DEPLOY_PROFILE" >"$tmp"
    mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  fi
  profile_log "installed template $id"
}

profile_show() {
  if [[ ! -f "$OLCRTC_DEPLOY_PROFILE" ]]; then
    echo "no deploy profile (using env defaults)"
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    jq . "$OLCRTC_DEPLOY_PROFILE"
  else
    cat "$OLCRTC_DEPLOY_PROFILE"
  fi
}

profile_component() {
  local key="$1"
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg k "$key" '.components[$k] == true' "$OLCRTC_DEPLOY_PROFILE" >/dev/null 2>&1
    return $?
  fi
  grep -q "\"$key\": true" "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null
}

profile_sanitize_warp_ru() {
  # RU VPS: WARP только если явно включён в features.env (olc-feature warp on / --with-warp).
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local ru warp
  ru="$(jq -r '.ru_vps // false' "$OLCRTC_DEPLOY_PROFILE")"
  warp="$(jq -r '.components.warp // false' "$OLCRTC_DEPLOY_PROFILE")"
  [[ "$ru" == "true" && "$warp" == "true" ]] || return 0
  local feat=0
  if [[ -f /etc/olcrtc-manager/features.env ]]; then
    # shellcheck disable=SC1091
    set -a
    source /etc/olcrtc-manager/features.env 2>/dev/null || true
    set +a
    [[ "${OLCRTC_ENABLE_WARP:-0}" == "1" ]] && feat=1
  fi
  if [[ "$feat" -eq 0 ]]; then
    local tmp
    tmp="$(mktemp)"
    jq '.components.warp = false' "$OLCRTC_DEPLOY_PROFILE" >"$tmp" && mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
    profile_log "RU VPS: WARP в профиле выключен (не включён в features.env). Используйте --with-warp или olc-feature warp on"
  fi
}

profile_apply_env() {
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 0
  if [[ "${OLCRTC_PROFILE_IGNORE:-0}" == "1" ]]; then
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  profile_sanitize_warp_ru
  local tor split zapret ru warp panel_access panel_listen_addr
  tor="$(jq -r '.components.tor // true' "$OLCRTC_DEPLOY_PROFILE")"
  split="$(jq -r '.components.split // true' "$OLCRTC_DEPLOY_PROFILE")"
  zapret="$(jq -r '.components.zapret // true' "$OLCRTC_DEPLOY_PROFILE")"
  ru="$(jq -r '.ru_vps // true' "$OLCRTC_DEPLOY_PROFILE")"
  warp="$(jq -r '.components.warp // false' "$OLCRTC_DEPLOY_PROFILE")"
  panel_access="$(jq -r '.panel.access // "ip"' "$OLCRTC_DEPLOY_PROFILE")"
  [[ "$panel_access" == "ssh" ]] || panel_access="ip"
  [[ "$panel_access" == "ssh" ]] && panel_listen_addr="127.0.0.1" || panel_listen_addr="0.0.0.0"
  if [[ "$(jq -r 'has("panel")' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo false)" != "true" ]]; then
    local tmp_panel
    tmp_panel="$(mktemp)"
    jq --arg access "$panel_access" --arg listen "$panel_listen_addr" \
      '.panel = {access: $access, listen_addr: $listen}' \
      "$OLCRTC_DEPLOY_PROFILE" >"$tmp_panel" && mv "$tmp_panel" "$OLCRTC_DEPLOY_PROFILE"
  fi

  # Если есть features.env, он имеет больший приоритет (пользователь менял через UI)
  if [[ -f /etc/olcrtc-manager/features.env ]]; then
    local _f_tor _f_split _f_zapret _f_warp
    _f_tor="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_TOR=' /etc/olcrtc-manager/features.env | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    _f_split="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_SPLIT=' /etc/olcrtc-manager/features.env | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    _f_zapret="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_ZAPRET=' /etc/olcrtc-manager/features.env | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    _f_warp="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_WARP=' /etc/olcrtc-manager/features.env | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    
    [[ "$_f_tor" == "1" ]] && tor="true"
    [[ "$_f_tor" == "0" ]] && tor="false"
    [[ "$_f_split" == "1" ]] && split="true"
    [[ "$_f_split" == "0" ]] && split="false"
    [[ "$_f_zapret" == "1" ]] && zapret="true"
    [[ "$_f_zapret" == "0" ]] && zapret="false"
    [[ "$_f_warp" == "1" ]] && warp="true"
    [[ "$_f_warp" == "0" ]] && warp="false"
    
    # Синхронизируем изменения обратно в deploy-profile.json
    local tmp
    tmp="$(mktemp)"
    jq --argjson t "$tor" --argjson s "$split" --argjson z "$zapret" --argjson w "$warp" \
      '.components.tor = $t | .components.split = $s | .components.zapret = $z | .components.warp = $w' \
      "$OLCRTC_DEPLOY_PROFILE" >"$tmp" && mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  else
    # Инициализируем features.env из профиля, чтобы UI видел правильное состояние
    install -d /etc/olcrtc-manager
    cat >/etc/olcrtc-manager/features.env <<EOF
# Olc-cost-l feature toggles (managed by /opt/Olc-cost-l/scripts/olc-feature.sh)
# Values: 1 = enabled (default), 0 = disabled
OLCRTC_ENABLE_ZAPRET=$([[ "$zapret" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_TOR=$([[ "$tor" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_SPLIT=$([[ "$split" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_WEBTUNNEL=$([[ "$tor" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_WARP=$([[ "$warp" == "true" ]] && echo 1 || echo 0)
EOF
  fi

  [[ "$tor" == "true" ]] && ENABLE_TOR=1 || ENABLE_TOR=0
  [[ "$split" == "true" ]] && ENABLE_SPLIT=1 || ENABLE_SPLIT=0
  [[ "$zapret" == "true" ]] && export OLCRTC_ENABLE_ZAPRET=1 || export OLCRTC_ENABLE_ZAPRET=0
  [[ "$ru" == "true" ]] && RU_VPS=1 || RU_VPS=0
  [[ "$warp" == "true" ]] && ENABLE_WARP=1 || ENABLE_WARP=0
  PANEL_ACCESS="$panel_access"
  PANEL_LISTEN_ADDR="$panel_listen_addr"

  export ENABLE_TOR ENABLE_SPLIT RU_VPS ENABLE_WARP PANEL_ACCESS PANEL_LISTEN_ADDR
  profile_log "applied $(jq -r '.profile_id // "custom"' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo "custom") (tor=$ENABLE_TOR split=$ENABLE_SPLIT zapret=${OLCRTC_ENABLE_ZAPRET:-1} warp=$ENABLE_WARP panel=$PANEL_ACCESS)"
  profile_log "Совет: для доустановки или обновления можно использовать короткую команду: olc-update"
}

profile_step_enabled() {
  local step="$1"
  case "$step" in
    packages|patches|sysctl|systemd|cron|cleanup-tmp|restart-manager|start-manager|webtunnel)
      return 0
      ;;
    tor|bridges)
      [[ "${ENABLE_TOR:-1}" -eq 1 ]]
      return
      ;;
    warp)
      [[ "${ENABLE_WARP:-0}" -eq 1 ]]
      return
      ;;
    split)
      [[ "${ENABLE_TOR:-1}" -eq 1 && "${ENABLE_SPLIT:-1}" -eq 1 && "${RU_VPS:-1}" -eq 1 ]]
      return
      ;;
    zapret)
      [[ "${OLCRTC_ENABLE_ZAPRET:-1}" -eq 1 && "${RU_VPS:-1}" -eq 1 ]]
      return
      ;;
    fetch-community-lists)
      [[ "${OLCRTC_ENABLE_ZAPRET:-1}" -eq 1 || ( "${ENABLE_SPLIT:-1}" -eq 1 && "${RU_VPS:-1}" -eq 1 ) ]]
      return
      ;;
    *)
      return 0
      ;;
  esac
}

# state_step wrapper — skip step when deploy profile disables component.
state_step_profile() {
  local name="$1"
  shift
  if ! profile_step_enabled "$name"; then
    echo "[state] skip $name (deploy profile)"
    return 0
  fi
  state_step "$name" "$@"
}

profile_list_templates() {
  local f
  for f in "$OLCRTC_PROFILES_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    basename "$f" .json
  done
}

# --- Live sync (UI ± / olc-profile sync) ---

profile_read_component() {
  local key="$1"
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r --arg k "$key" '.components[$k] // false' "$OLCRTC_DEPLOY_PROFILE"
}

profile_write_json() {
  local json="$1"
  profile_ensure_dir
  printf '%s\n' "$json" >"$OLCRTC_DEPLOY_PROFILE"
}

profile_set_component() {
  local key="$1"
  local val="$2" # true|false
  profile_ensure_dir
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || profile_from_flags
  command -v jq >/dev/null 2>&1 || {
    profile_log "jq required for profile_set_component"
    return 1
  }
  local tmp json
  tmp="$(mktemp)"
  jq --arg k "$key" --argjson v "$([[ "$val" == true ]] && echo true || echo false)" \
    '.components[$k] = $v | .updated_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
    "$OLCRTC_DEPLOY_PROFILE" >"$tmp"
  mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  profile_refresh_id_label
  profile_log "component $key=$val"
}

profile_refresh_id_label() {
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local matched=""
  local tpl id
  for tpl in "$OLCRTC_PROFILES_DIR"/*.json; do
    [[ -f "$tpl" ]] || continue
    id="$(basename "$tpl" .json)"
    [[ "$id" == "custom" ]] && continue
    if jq -e --slurpfile t "$tpl" \
      '(.components == $t[0].components) and ((.ru_vps // true) == ($t[0].ru_vps // true))' \
      "$OLCRTC_DEPLOY_PROFILE" >/dev/null 2>&1; then
      matched="$id"
      break
    fi
  done
  local tmp
  tmp="$(mktemp)"
  if [[ -n "$matched" ]]; then
    jq --arg id "$matched" --arg label "$(jq -r '.label' "${OLCRTC_PROFILES_DIR}/${matched}.json")" \
      '.profile_id = $id | .label = $label' "$OLCRTC_DEPLOY_PROFILE" >"$tmp"
  else
    jq '.profile_id = "custom" | .label = "Смешанный профиль (UI/CLI)"' \
      "$OLCRTC_DEPLOY_PROFILE" >"$tmp"
  fi
  mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
}

# Called after panel ± install/uninstall job.
profile_after_component_job() {
  local component="$1"
  local action="$2" # install|uninstall
  local enabled="false"
  [[ "$action" == "install" ]] && enabled="true"

  case "$component" in
    zapret|split|warp)
      profile_set_component "$component" "$enabled"
      ;;
    tor)
      profile_set_component tor "$enabled"
      if [[ "$action" == "install" ]]; then
        profile_set_component bridges true
      else
        profile_set_component split false
        profile_set_component bridges false
      fi
      ;;
    bridges)
      profile_set_component bridges "$enabled"
      if [[ "$action" == "install" ]]; then
        profile_set_component tor true
      fi
      ;;
    *)
      profile_log "unknown component for profile sync: $component"
      return 1
      ;;
  esac

  if [[ "$component" == "warp" && "$action" == "install" ]]; then
    profile_set_component tor false
    profile_set_component split false
    profile_set_component bridges false
    profile_set_component zapret false
    local tmp
    tmp="$(mktemp)"
    jq '.ru_vps = false' "$OLCRTC_DEPLOY_PROFILE" >"$tmp" && mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  fi
  if [[ "$component" == "tor" && "$action" == "install" ]]; then
    profile_set_component warp false
  fi
  profile_refresh_id_label
  profile_log "after component job: $component $action → $(jq -c '.components' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo '?')"
}

# Detect packages/config on disk; does NOT read feature toggles (on/off).
profile_detect_installed() {
  local tor=0 split=0 zapret=0 bridges=0 warp=0 ru=1

  dpkg-query -W -f='${Status}' tor 2>/dev/null | grep -q 'install ok installed' && tor=1
  [[ -x /opt/zapret/nfq/nfqws ]] && zapret=1
  command -v warp-cli >/dev/null 2>&1 && warp=1
  if [[ -f /var/lib/olcrtc/lists/ru-direct-domains.txt ]] \
    || [[ -f /var/lib/olcrtc/lists/panel-carrier-hosts.txt ]]; then
    split=1
  fi
  if [[ -f /etc/tor/bridges.conf ]] && grep -qE '^[[:space:]]*Bridge ' /etc/tor/bridges.conf 2>/dev/null; then
    bridges=1
  fi
  [[ "$tor" -eq 0 && "$split" -eq 0 && "$zapret" -eq 0 && "$warp" -eq 0 ]] && ru=0

  printf '%s %s %s %s %s %s\n' "$tor" "$split" "$zapret" "$bridges" "$warp" "$ru"
}

# Merge detected install state into deploy profile (one file, not multiple fingerprints).
profile_sync_from_installed() {
  profile_ensure_dir
  read -r tor split zapret bridges warp ru <<<"$(profile_detect_installed)"
  if [[ ! -f "$OLCRTC_DEPLOY_PROFILE" ]]; then
    profile_from_flags "$tor" "$split" "$zapret" "$bridges" "$ru" "profile-sync"
    profile_refresh_id_label
    return 0
  fi
  command -v jq >/dev/null 2>&1 || return 0
  local tmp
  tmp="$(mktemp)"
  jq \
    --argjson tor "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
    --argjson split "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
    --argjson zapret "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
    --argjson bridges "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
    --argjson warp "$([[ "$warp" -eq 1 ]] && echo true || echo false)" \
    --argjson ru "$([[ "$ru" -eq 1 ]] && echo true || echo false)" \
    '.components = {tor:$tor, split:$split, zapret:$zapret, bridges:$bridges, warp:$warp}
     | .ru_vps = $ru
     | .synced_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
    "$OLCRTC_DEPLOY_PROFILE" >"$tmp"
  mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  profile_refresh_id_label
  profile_log "synced from installed packages → $(jq -r '.profile_id' "$OLCRTC_DEPLOY_PROFILE")"
}

# Honor features.env after update maintenance (toggle off ≠ remove from profile).
profile_apply_runtime_toggles() {
  local env=/etc/olcrtc-manager/features.env
  [[ -f "$env" ]] || return 0
  # shellcheck disable=SC1090
  set -a; source "$env"; set +a

  if [[ "${OLCRTC_ENABLE_TOR:-1}" != "1" ]]; then
    systemctl stop tor@default.service 2>/dev/null || true
    systemctl disable tor@default.service 2>/dev/null || true
    profile_log "runtime: tor left stopped (features.env)"
  fi
  if [[ "${OLCRTC_ENABLE_WARP:-0}" != "1" ]]; then
    warp-cli disconnect 2>/dev/null || true
    profile_log "runtime: warp disconnected (features.env)"
  fi
  if [[ "${OLCRTC_ENABLE_ZAPRET:-1}" != "1" ]]; then
    systemctl stop zapret.service 2>/dev/null || true
    pkill -9 nfqws 2>/dev/null || true
    profile_log "runtime: zapret left stopped (features.env)"
  fi
}
