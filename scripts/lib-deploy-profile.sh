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

  if [[ "$tor" -eq 0 ]]; then
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
      --argjson tor "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
      --argjson split "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
      --argjson zapret "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
      --argjson bridges "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
      --argjson ru "$([[ "$ru" -eq 1 ]] && echo true || echo false)" \
      '{
        schema: 1,
        profile_id: $id,
        label: $label,
        components: { tor: $tor, split: $split, zapret: $zapret, bridges: $bridges },
        ru_vps: $ru,
        update_mode: "incremental",
        created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        install_script_fingerprint: $fp
      }' >"$OLCRTC_DEPLOY_PROFILE"
  else
    printf '{"schema":1,"profile_id":"%s","label":"%s","components":{"tor":%s,"split":%s,"zapret":%s,"bridges":%s}}\n' \
      "$PROFILE_ID" "$PROFILE_LABEL" \
      "$([[ "$tor" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$split" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$zapret" -eq 1 ]] && echo true || echo false)" \
      "$([[ "$bridges" -eq 1 ]] && echo true || echo false)" \
      >"$OLCRTC_DEPLOY_PROFILE"
  fi
  profile_log "saved $PROFILE_ID → $OLCRTC_DEPLOY_PROFILE"
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

profile_apply_env() {
  [[ -f "$OLCRTC_DEPLOY_PROFILE" ]] || return 0
  if [[ "${OLCRTC_PROFILE_IGNORE:-0}" == "1" ]]; then
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  local tor split zapret ru
  tor="$(jq -r '.components.tor // true' "$OLCRTC_DEPLOY_PROFILE")"
  split="$(jq -r '.components.split // true' "$OLCRTC_DEPLOY_PROFILE")"
  zapret="$(jq -r '.components.zapret // true' "$OLCRTC_DEPLOY_PROFILE")"
  ru="$(jq -r '.ru_vps // true' "$OLCRTC_DEPLOY_PROFILE")"

  [[ "$tor" == "true" ]] && ENABLE_TOR=1 || ENABLE_TOR=0
  [[ "$split" == "true" ]] && ENABLE_SPLIT=1 || ENABLE_SPLIT=0
  [[ "$zapret" == "true" ]] && export OLCRTC_ENABLE_ZAPRET=1 || export OLCRTC_ENABLE_ZAPRET=0
  [[ "$ru" == "true" ]] && RU_VPS=1 || RU_VPS=0

  export ENABLE_TOR ENABLE_SPLIT RU_VPS
  profile_log "applied $(jq -r '.profile_id // "custom"' "$OLCRTC_DEPLOY_PROFILE") (tor=$ENABLE_TOR split=$ENABLE_SPLIT zapret=${OLCRTC_ENABLE_ZAPRET:-1})"
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
