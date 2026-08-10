#!/usr/bin/env bash
# Deploy profile: records which stack components are installed on this VPS.
# Desired runtime on/off state lives only in features.env; observed runtime state
# is queried from systemd/processes and is never written back into this profile.
# Read on olc-update so foreign/minimal hosts skip heavy steps.
#
# File: /etc/olcrtc-manager/deploy-profile.json
# Templates: $REPO_ROOT/data/deploy-profiles/*.json
#
# shellcheck shell=bash

: "${OLCRTC_DEPLOY_PROFILE:=/etc/olcrtc-manager/deploy-profile.json}"
: "${OLCRTC_PROFILES_DIR:=${OLC_REPO_ROOT:-}/data/deploy-profiles}"
: "${OLCRTC_FEATURES_ENV:=/etc/olcrtc-manager/features.env}"
: "${OLCRTC_COMPONENT_REMOVED_DIR:=/var/lib/olcrtc/component-removed}"
: "${OLCRTC_SPLIT_LISTS_DIR:=/var/lib/olcrtc/lists}"
: "${OLCRTC_TOR_BRIDGES_CONF:=/etc/tor/bridges.conf}"
: "${OLCRTC_ZAPRET_BIN:=/opt/zapret/nfq/nfqws}"

profile_log() {
  # Тихий режим: сводка профиля показывается вызывающим кодом (заголовок экрана)
  [[ "${OLC_PROFILE_LOG_QUIET:-0}" == "1" ]] && return 0
  # При активном animated-баре — под бар, чтобы не наложиться на спиннер
  if declare -f olc_spinner_active >/dev/null 2>&1 && olc_spinner_active \
     && declare -f olc_progress_msg >/dev/null 2>&1; then
    olc_progress_msg "[profile] $*"
    return 0
  fi
  echo "[profile] $*"
}

profile_ensure_dir() {
  mkdir -p "$(dirname "$OLCRTC_DEPLOY_PROFILE")"
}

profile_feature_toggle_write() {
  local env="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$env")"
  if grep -q "^${key}=" "$env" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env"
  else
    printf '%s=%s\n' "$key" "$value" >>"$env"
  fi
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
  local panel_tls_mode="${10:-${PANEL_TLS_MODE:-}}"
  case "$panel_tls_mode" in
    letsencrypt) panel_tls=1 ;;
    selfsigned|https) panel_tls=1; panel_tls_mode="selfsigned" ;;
    http) panel_tls=0 ;;
    *) [[ "$panel_tls" -eq 1 ]] && panel_tls_mode="selfsigned" || panel_tls_mode="http" ;;
  esac
  local panel_listen_addr="0.0.0.0"
  [[ "$panel_access" == "ssh" ]] && panel_listen_addr="127.0.0.1" || panel_access="ip"

  case "$tor:$split:$zapret:$bridges:$warp" in
    1:1:1:1:0) PROFILE_ID="ru-full"; PROFILE_LABEL="RU VPS: полный стек" ;;
    0:0:1:0:0) PROFILE_ID="zapret-only"; PROFILE_LABEL="Zapret + панель" ;;
    0:0:0:0:1) PROFILE_ID="warp-only"; PROFILE_LABEL="Cloudflare WARP + панель" ;;
    1:0:0:0:0) PROFILE_ID="tor-only"; PROFILE_LABEL="Tor + панель" ;;
    1:0:0:1:0) PROFILE_ID="tor-bridges"; PROFILE_LABEL="Tor + мосты + панель" ;;
    1:1:0:0:0) PROFILE_ID="tor-split"; PROFILE_LABEL="Tor + split + панель" ;;
    0:0:0:0:0) PROFILE_ID="panel-only"; PROFILE_LABEL="Только панель" ;;
    *) PROFILE_ID="custom"; PROFILE_LABEL="Выборочный набор компонентов" ;;
  esac

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
      --arg panel_tls_mode "$panel_tls_mode" \
      --argjson panel_tls "$([[ "$panel_tls" -eq 1 ]] && echo true || echo false)" \
      --argjson tor "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
      --argjson split "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
      --argjson zapret "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
      --argjson bridges "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
      --argjson warp "$([[ "$warp" -eq 1 ]] && echo true || echo false)" \
      --argjson ru "$([[ "$ru" -eq 1 ]] && echo true || echo false)" \
      '{
        schema: 2,
        profile_id: $id,
        label: $label,
        components: { tor: $tor, split: $split, zapret: $zapret, bridges: $bridges, warp: $warp },
        panel: { access: $panel_access, listen_addr: $panel_listen_addr, tls: $panel_tls, tls_mode: $panel_tls_mode },
        ru_vps: $ru,
        update_mode: "incremental",
        created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        install_script_fingerprint: $fp
      }' >"$OLCRTC_DEPLOY_PROFILE"
  else
    printf '{"schema":2,"profile_id":"%s","label":"%s","components":{"tor":%s,"split":%s,"zapret":%s,"bridges":%s,"warp":%s},"panel":{"access":"%s","listen_addr":"%s","tls":%s,"tls_mode":"%s"}}\n' \
      "$PROFILE_ID" "$PROFILE_LABEL" \
      "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$warp" -eq 1 ]] && echo true || echo false)" \
      "$panel_access" "$panel_listen_addr" \
      "$([[ "$panel_tls" -eq 1 ]] && echo true || echo false)" "$panel_tls_mode" \
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

profile_set_panel_tls() {
  local requested="${1:-0}"
  local tls=0 mode="http"
  case "$requested" in
    letsencrypt) tls=1; mode="letsencrypt" ;;
    selfsigned|https|1|true) tls=1; mode="selfsigned" ;;
    http|0|false|"") ;;
    *) return 1 ;;
  esac
  profile_ensure_dir
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || profile_from_flags
  command -v jq >/dev/null 2>&1 || return 0
  local tmp
  tmp="$(mktemp)"
  jq --argjson tls "$([[ "$tls" -eq 1 ]] && echo true || echo false)" --arg mode "$mode" \
    '.panel.tls = $tls | .panel.tls_mode = $mode | .updated_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
    "$OLCRTC_DEPLOY_PROFILE" >"$tmp" && mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  profile_log "panel tls=$tls mode=$mode"
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
  # Installed Tor and WARP may coexist. Runtime exclusivity is enforced by
  # olc-feature.sh and must not mutate the installed profile.
  return 0
}

profile_apply_env() {
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 0
  profile_migrate_schema
  if [[ "${OLCRTC_PROFILE_IGNORE:-0}" == "1" ]]; then
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  profile_sanitize_warp_ru
  local tor split zapret bridges ru warp panel_access panel_listen_addr panel_tls panel_tls_mode
  tor="$(jq -r '.components.tor // true' "$OLCRTC_DEPLOY_PROFILE")"
  split="$(jq -r '.components.split // true' "$OLCRTC_DEPLOY_PROFILE")"
  zapret="$(jq -r '.components.zapret // true' "$OLCRTC_DEPLOY_PROFILE")"
  bridges="$(jq -r '.components.bridges // false' "$OLCRTC_DEPLOY_PROFILE")"
  ru="$(jq -r '.ru_vps // true' "$OLCRTC_DEPLOY_PROFILE")"
  warp="$(jq -r '.components.warp // false' "$OLCRTC_DEPLOY_PROFILE")"
  panel_access="$(jq -r '.panel.access // "ip"' "$OLCRTC_DEPLOY_PROFILE")"
  panel_tls="$(jq -r '.panel.tls // false' "$OLCRTC_DEPLOY_PROFILE")"
  panel_tls_mode="$(jq -r '.panel.tls_mode // empty' "$OLCRTC_DEPLOY_PROFILE")"
  [[ "$panel_access" == "ssh" ]] || panel_access="ip"
  [[ "$panel_tls" == "true" ]] && panel_tls=1 || panel_tls=0
  case "$panel_tls_mode" in
    letsencrypt) panel_tls=1 ;;
    selfsigned) panel_tls=1 ;;
    *) [[ "$panel_tls" -eq 1 ]] && panel_tls_mode="selfsigned" || panel_tls_mode="http" ;;
  esac
  [[ "$panel_access" == "ssh" ]] && panel_listen_addr="127.0.0.1" || panel_listen_addr="0.0.0.0"
  if [[ "$(jq -r 'has("panel")' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo false)" != "true" ]]; then
    local tmp_panel
    tmp_panel="$(mktemp)"
    jq --arg access "$panel_access" --arg listen "$panel_listen_addr" \
      '.panel = {access: $access, listen_addr: $listen, tls: false, tls_mode: "http"}' \
      "$OLCRTC_DEPLOY_PROFILE" >"$tmp_panel" && mv "$tmp_panel" "$OLCRTC_DEPLOY_PROFILE"
  fi

  # features.env is the authoritative desired runtime state. It must never
  # rewrite the installed component composition stored in the deploy profile.
  if [[ -f "$OLCRTC_FEATURES_ENV" ]]; then
    local _f_tor _f_split _f_zapret _f_bridges _f_webtunnel _f_warp
    _f_tor="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_TOR=' "$OLCRTC_FEATURES_ENV" | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    _f_split="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_SPLIT=' "$OLCRTC_FEATURES_ENV" | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    _f_zapret="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_ZAPRET=' "$OLCRTC_FEATURES_ENV" | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    _f_bridges="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_BRIDGES=' "$OLCRTC_FEATURES_ENV" | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    _f_webtunnel="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_WEBTUNNEL=' "$OLCRTC_FEATURES_ENV" | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    if [[ -z "$_f_bridges" ]]; then
      _f_bridges="$_f_webtunnel"
    fi
    _f_warp="$(grep -E '^[[:space:]]*OLCRTC_ENABLE_WARP=' "$OLCRTC_FEATURES_ENV" | cut -d= -f2 | tr -d '"'"'" | tail -1)"
    # Tor is the parent runtime for split routing and bridge transports.
    # Old backups may not contain all dependent flags, so normalize them here.
    if [[ "$_f_tor" == "0" ]]; then
      _f_split="0"
      _f_bridges="0"
      profile_feature_toggle_write "$OLCRTC_FEATURES_ENV" OLCRTC_ENABLE_SPLIT 0
      profile_feature_toggle_write "$OLCRTC_FEATURES_ENV" OLCRTC_ENABLE_BRIDGES 0
      profile_feature_toggle_write "$OLCRTC_FEATURES_ENV" OLCRTC_ENABLE_WEBTUNNEL 0
    fi

    
    export OLCRTC_ENABLE_TOR="${_f_tor:-0}"
    export OLCRTC_ENABLE_SPLIT="${_f_split:-0}"
    export OLCRTC_ENABLE_ZAPRET="${_f_zapret:-0}"
    export OLCRTC_ENABLE_BRIDGES="${_f_bridges:-0}"
    export OLCRTC_ENABLE_WEBTUNNEL="${_f_webtunnel:-0}"
    export OLCRTC_ENABLE_WARP="${_f_warp:-0}"
  else
    # Инициализируем features.env из профиля, чтобы UI видел правильное состояние
    install -d "$(dirname "$OLCRTC_FEATURES_ENV")"
    cat >"$OLCRTC_FEATURES_ENV" <<EOF
# Olc-cost-l feature toggles (managed by /opt/Olc-cost-l/scripts/olc-feature.sh)
# Values: 1 = enabled (default), 0 = disabled
OLCRTC_ENABLE_ZAPRET=$([[ "$zapret" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_TOR=$([[ "$tor" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_SPLIT=$([[ "$split" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_BRIDGES=$([[ "$bridges" == "true" ]] && echo 1 || echo 0)
OLCRTC_ENABLE_WEBTUNNEL=0
OLCRTC_ENABLE_WARP=$([[ "$warp" == "true" ]] && echo 1 || echo 0)
EOF
    export OLCRTC_ENABLE_TOR=$([[ "$tor" == "true" ]] && echo 1 || echo 0)
    export OLCRTC_ENABLE_SPLIT=$([[ "$split" == "true" ]] && echo 1 || echo 0)
    export OLCRTC_ENABLE_ZAPRET=$([[ "$zapret" == "true" ]] && echo 1 || echo 0)
    export OLCRTC_ENABLE_BRIDGES=$([[ "$bridges" == "true" ]] && echo 1 || echo 0)
    export OLCRTC_ENABLE_WEBTUNNEL=0
    export OLCRTC_ENABLE_WARP=$([[ "$warp" == "true" ]] && echo 1 || echo 0)
  fi

  [[ "$tor" == "true" ]] && ENABLE_TOR=1 || ENABLE_TOR=0
  [[ "$split" == "true" ]] && ENABLE_SPLIT=1 || ENABLE_SPLIT=0
  [[ "$zapret" == "true" ]] && ENABLE_ZAPRET=1 || ENABLE_ZAPRET=0
  [[ "$bridges" == "true" ]] && ENABLE_BRIDGES=1 || ENABLE_BRIDGES=0
  [[ "$ru" == "true" ]] && RU_VPS=1 || RU_VPS=0
  [[ "$warp" == "true" ]] && ENABLE_WARP=1 || ENABLE_WARP=0
  PANEL_ACCESS="$panel_access"
  PANEL_LISTEN_ADDR="$panel_listen_addr"
  PANEL_TLS="$panel_tls"
  PANEL_TLS_MODE="$panel_tls_mode"

  export ENABLE_TOR ENABLE_SPLIT ENABLE_ZAPRET ENABLE_BRIDGES RU_VPS ENABLE_WARP PANEL_ACCESS PANEL_LISTEN_ADDR PANEL_TLS PANEL_TLS_MODE
  profile_log "applied $(jq -r '.profile_id // "custom"' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo "custom") (installed: tor=$ENABLE_TOR split=$ENABLE_SPLIT zapret=$ENABLE_ZAPRET bridges=$ENABLE_BRIDGES warp=$ENABLE_WARP; enabled: tor=${OLCRTC_ENABLE_TOR:-0} split=${OLCRTC_ENABLE_SPLIT:-0} zapret=${OLCRTC_ENABLE_ZAPRET:-0} bridges=${OLCRTC_ENABLE_BRIDGES:-0} warp=${OLCRTC_ENABLE_WARP:-0})"
  # Совет про olc-update только при первой установке (не при UPDATE режиме)
  if [[ "${OLCRTC_UPDATE_MODE:-0}" != "1" ]]; then
    profile_log "Совет: для доустановки или обновления можно использовать короткую команду: olc-update"
  fi
}

profile_step_enabled() {
  local step="$1"
  case "$step" in
    packages|patches|sysctl|systemd|cron|cleanup-tmp|restart-manager|start-manager)
      return 0
      ;;
    tor)
      [[ "${ENABLE_TOR:-0}" -eq 1 ]]
      return
      ;;
    bridges)
      [[ "${ENABLE_BRIDGES:-0}" -eq 1 ]]
      return
      ;;
    warp)
      [[ "${ENABLE_WARP:-0}" -eq 1 ]]
      return
      ;;
    split)
      [[ "${ENABLE_SPLIT:-0}" -eq 1 && "${RU_VPS:-1}" -eq 1 ]]
      return
      ;;
    zapret)
      [[ "${ENABLE_ZAPRET:-0}" -eq 1 && "${RU_VPS:-1}" -eq 1 ]]
      return
      ;;
    fetch-community-lists)
      [[ "${ENABLE_ZAPRET:-0}" -eq 1 || ( "${ENABLE_SPLIT:-0}" -eq 1 && "${RU_VPS:-1}" -eq 1 ) ]]
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
    # Шаг учитывается в прогрессе, даже если отключён профилем —
    # иначе проценты/счётчик «шаг N/M» съезжают и бар не доходит до 100%
    _OLCRTC_STEP_NUM=$(( ${_OLCRTC_STEP_NUM:-0} + 1 ))
    if declare -f _olc_progress_publish >/dev/null 2>&1; then
      _olc_progress_publish "$_OLCRTC_STEP_NUM" "${OLCRTC_TOTAL_STEPS:-0}" "$name"
    fi
    if declare -f olc_spinner_active >/dev/null 2>&1 && olc_spinner_active \
       && declare -f olc_progress_msg >/dev/null 2>&1; then
      olc_progress_msg "пропуск: ${name} (отключён в профиле)"
    else
      echo "[state] skip $name (deploy profile)"
    fi
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
    '.schema = 2 | .components[$k] = $v | .updated_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
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
    tor|bridges)
      # Dependencies affect runtime availability, not installed composition.
      # Runtime toggles handle the dependency cascade separately.
      profile_set_component "$component" "$enabled"
      ;;
    *)
      profile_log "unknown component for profile sync: $component"
      return 1
      ;;
  esac

  profile_refresh_id_label
  profile_log "after component job: $component $action → $(jq -c '.components' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo '?')"
}

# Detect packages/config on disk; does NOT read feature toggles (on/off).
profile_detect_installed() {
  local tor=0 split=0 zapret=0 bridges=0 warp=0 ru=1

  dpkg-query -W -f='${Status}' tor 2>/dev/null | grep -q 'install ok installed' && tor=1
  [[ -x "$OLCRTC_ZAPRET_BIN" ]] && zapret=1
  command -v warp-cli >/dev/null 2>&1 && warp=1
  if compgen -G "$OLCRTC_SPLIT_LISTS_DIR/*.txt" >/dev/null \
    || compgen -G "$OLCRTC_SPLIT_LISTS_DIR/disabled/*.txt" >/dev/null; then
    split=1
  fi
  if command -v obfs4proxy >/dev/null 2>&1 || command -v snowflake-client >/dev/null 2>&1 \
    || command -v webtunnel-client >/dev/null 2>&1 \
    || { [[ -f "$OLCRTC_TOR_BRIDGES_CONF" ]] && grep -qE '^[[:space:]]*Bridge ' "$OLCRTC_TOR_BRIDGES_CONF" 2>/dev/null; }; then
    bridges=1
  fi
  local component
  for component in tor split zapret bridges warp; do
    [[ -e "$OLCRTC_COMPONENT_REMOVED_DIR/$component" ]] && printf -v "$component" 0
  done
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
    '.schema = 2 | .components = {tor:$tor, split:$split, zapret:$zapret, bridges:$bridges, warp:$warp}
     | .ru_vps = $ru
     | .synced_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
    "$OLCRTC_DEPLOY_PROFILE" >"$tmp"
  mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  profile_refresh_id_label
  profile_log "synced from installed packages → $(jq -r '.profile_id' "$OLCRTC_DEPLOY_PROFILE")"
}

profile_migrate_schema() {
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local schema
  schema="$(jq -r '.schema // 1' "$OLCRTC_DEPLOY_PROFILE" 2>/dev/null || echo 1)"
  [[ "$schema" =~ ^[0-9]+$ ]] || schema=1
  (( schema >= 2 )) && return 0
  local tor split zapret bridges warp ru backup tmp
  read -r tor split zapret bridges warp ru <<<"$(profile_detect_installed)"
  backup="${OLCRTC_DEPLOY_PROFILE}.bak-schema1-$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "$OLCRTC_DEPLOY_PROFILE" "$backup"
  tmp="$(mktemp)"
  jq \
    --argjson tor "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
    --argjson split "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
    --argjson zapret "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
    --argjson bridges "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
    --argjson warp "$([[ "$warp" -eq 1 ]] && echo true || echo false)" \
    --arg backup "$backup" \
    '.legacy_schema1_components = (.components // {})
     | .schema = 2
     | .components = {tor:$tor, split:$split, zapret:$zapret, bridges:$bridges, warp:$warp}
     | .component_state_model = "installed-profile-vs-enabled-runtime"
     | .schema_migrated_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
     | .schema1_backup = $backup' \
    "$OLCRTC_DEPLOY_PROFILE" >"$tmp"
  mv "$tmp" "$OLCRTC_DEPLOY_PROFILE"
  profile_refresh_id_label
  profile_log "migrated deploy profile schema 1 -> 2"
}

# Honor features.env after update maintenance (toggle off ≠ remove from profile).
profile_apply_runtime_toggles() {
  local env="$OLCRTC_FEATURES_ENV"
  [[ -f "$env" ]] || return 0
  # shellcheck disable=SC1090
  set -a; source "$env"; set +a

  if [[ "${OLCRTC_ENABLE_TOR:-1}" != "1" ]]; then
    systemctl stop tor@default.service 2>/dev/null || true
    systemctl disable tor@default.service 2>/dev/null || true
    profile_feature_toggle_write "$env" OLCRTC_ENABLE_SPLIT 0
    profile_feature_toggle_write "$env" OLCRTC_ENABLE_BRIDGES 0
    profile_feature_toggle_write "$env" OLCRTC_ENABLE_WEBTUNNEL 0
    OLCRTC_ENABLE_SPLIT=0
    OLCRTC_ENABLE_BRIDGES=0
    OLCRTC_ENABLE_WEBTUNNEL=0
    profile_log "runtime: tor left stopped (features.env)"
  fi
  if [[ "${OLCRTC_ENABLE_SPLIT:-0}" != "1" ]]; then
    systemctl disable --now olcrtc-split-expand.timer 2>/dev/null || true
    profile_log "runtime: split timer left stopped (features.env)"
  fi
  if [[ "${OLCRTC_ENABLE_BRIDGES:-0}" != "1" ]]; then
    local unit
    for unit in olcrtc-tor-bridge-pool olcrtc-tor-bridge-monitor olcrtc-tor-bridge-deep; do
      systemctl disable --now "${unit}.timer" 2>/dev/null || true
    done
    profile_log "runtime: bridge timers left stopped (features.env)"
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
