#!/usr/bin/env bash
# Versioned export/import of panel data through the local manager API.
set -euo pipefail

CONFIG="${OLCRTC_MANAGER_CONFIG:-/etc/olcrtc-manager/config.json}"
ENVF="${OLCRTC_MANAGER_ENV_FILE:-/etc/olcrtc-manager/panel.env}"

die() { echo "[olc-backup] ERROR: $*" >&2; exit 1; }
log() { echo "[olc-backup] $*" >&2; }

[[ "$(id -u)" -eq 0 ]] || exec sudo -E bash "$0" "$@"

load_panel_env() {
  OLCRTC_MANAGER_USER=""
  OLCRTC_MANAGER_PASS=""
  OLCRTC_MANAGER_TLS_CERT=""
  OLCRTC_MANAGER_TLS_KEY=""
  OLCRTC_MANAGER_PORT=""
  if [[ -f "$ENVF" ]]; then
    set +u
    # panel.env is a root-owned installer/manager configuration file.
    # shellcheck disable=SC1090
    source "$ENVF"
    set -u
  fi
}

load_panel_env
port="${OLCRTC_MANAGER_PORT:-8888}"
if [[ -f "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  port="$(jq -r --arg fallback "$port" '.port // ($fallback | tonumber)' "$CONFIG" 2>/dev/null || echo "$port")"
fi
user="${OLCRTC_MANAGER_USER:-admin}"
pass="${OLCRTC_MANAGER_PASS:-}"
scheme=http
declare -a curl_tls=()
if [[ -n "${OLCRTC_MANAGER_TLS_CERT:-}" && -n "${OLCRTC_MANAGER_TLS_KEY:-}" ]]; then
  scheme=https
  # Local loopback does not necessarily match the public-IP certificate SAN.
  curl_tls=(-k)
fi

# A retained TLS path in panel.env does not prove that the currently running
# manager actually serves TLS (for example during an interrupted migration).
# Probe the expected protocol first, then the alternative, without changing
# the public deploy profile or certificate configuration.
select_loopback_base() {
  local expected="$scheme" alternative=http
  [[ "$expected" == "http" ]] && alternative=https
  if curl -ksS --max-time 5 -o /dev/null "$expected://127.0.0.1:${port}/api/auth/me" 2>/dev/null; then
    scheme="$expected"
  elif curl -ksS --max-time 5 -o /dev/null "$alternative://127.0.0.1:${port}/api/auth/me" 2>/dev/null; then
    scheme="$alternative"
  else
    die "manager is not reachable on HTTP or HTTPS loopback port $port"
  fi
  curl_tls=()
  [[ "$scheme" == "https" ]] && curl_tls=(-k)
  base="${scheme}://127.0.0.1:${port}"
}

select_loopback_base

usage() {
  cat <<'EOF'
Usage:
  sudo olc-backup export [file.json]
  sudo olc-backup import <file.json> [--missing-components skip|install] [--confirm-foreign-host]
  sudo olc-backup import-first-run <file.json> [--missing-components skip|install] [--confirm-foreign-host]
EOF
}

request_import() {
  local endpoint="$1" input="$2" missing="$3" foreign="$4" use_auth="$5"
  local query="" sep="?"
  if [[ -n "$missing" ]]; then query="${sep}missing_components=${missing}"; sep='&'; fi
  if [[ "$foreign" -eq 1 ]]; then query="${query}${sep}confirm_foreign_host=1"; fi
  local response_file status
  response_file="$(mktemp /tmp/olc-backup-response-XXXXXX.json)"
  trap 'rm -f "$response_file"' RETURN
  declare -a auth=()
  [[ "$use_auth" -eq 1 ]] && auth=(-u "${user}:${pass}")
  status="$(curl -sS "${curl_tls[@]}" "${auth[@]}" --max-time 180 \
    -o "$response_file" -w '%{http_code}' -X POST "$base$endpoint$query" \
    -H 'Content-Type: application/json' --data-binary @"$input")" \
    || die "import request failed"
  if [[ ! "$status" =~ ^2 ]]; then
    cat "$response_file" >&2 || true
    die "import failed: HTTP $status"
  fi
  cat "$response_file"
  trap - RETURN
  rm -f "$response_file"
}

install_requested_components() {
  local response="$1"
  command -v jq >/dev/null 2>&1 || die "jq is required to install missing components"
  mapfile -t requested < <(jq -r '.install_components[]? // empty' "$response")
  [[ "${#requested[@]}" -gt 0 ]] || return 0
  load_panel_env
  user="${OLCRTC_MANAGER_USER:-admin}"
  pass="${OLCRTC_MANAGER_PASS:-}"
  for component in "${requested[@]}"; do
    log "installing missing component: $component"
    start="$(curl -sS "${curl_tls[@]}" -u "${user}:${pass}" --max-time 60 \
      -X POST "$base/api/components/$component/install")" || die "cannot start component install: $component"
    job="$(jq -r '.job_id // empty' <<<"$start")"
    [[ -n "$job" ]] || die "component install did not return job_id: $component"
    deadline=$((SECONDS + 900))
    while (( SECONDS < deadline )); do
      jobs="$(curl -sS "${curl_tls[@]}" -u "${user}:${pass}" --max-time 30 "$base/api/components/jobs")" || true
      status="$(jq -r --arg c "$component" --arg j "$job" '[.jobs[]? | select(.component == $c and .job_id == $j)][0].status // "running"' <<<"$jobs")"
      case "$status" in
        done) log "component installed: $component"; break ;;
        failed) die "component install failed: $component (job $job)" ;;
      esac
      sleep 2
    done
    [[ "$status" == "done" ]] || die "component install timed out: $component"
  done
}

cmd="${1:-}"; shift || true
case "$cmd" in
  export)
    out="${1:-olc-backup-$(date -u +%Y%m%d-%H%M%S).json}"
    [[ ! -e "$out" ]] || die "refusing to overwrite existing file: $out"
    tmp="$(mktemp "${out}.tmp.XXXXXX")"
    curl -fsS "${curl_tls[@]}" -u "${user}:${pass}" --max-time 180 \
      "$base/api/backup/export" -o "$tmp" \
      || { rm -f "$tmp"; die "export failed (manager/auth/TLS)"; }
    jq -e '.olc_backup == true' "$tmp" >/dev/null 2>&1 \
      || { rm -f "$tmp"; die "manager returned an invalid backup"; }
    chmod 0600 "$tmp"
    mv "$tmp" "$out"
    log "saved: $out"
    ;;
  import|import-first-run)
    in="${1:-}"; shift || true
    [[ -n "$in" && -f "$in" ]] || die "specify an existing backup file"
    command -v jq >/dev/null 2>&1 || die "jq is required"
    jq -e '.olc_backup == true' "$in" >/dev/null || die "not an Olc-cost-l backup"
    missing=""; foreign=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --missing-components)
          shift; missing="${1:-}"; [[ "$missing" == "skip" || "$missing" == "install" ]] || die "missing-components must be skip or install" ;;
        --confirm-foreign-host) foreign=1 ;;
        *) die "unknown import option: $1" ;;
      esac
      shift
    done
    endpoint=/api/backup/import; use_auth=1
    if [[ "$cmd" == "import-first-run" ]]; then endpoint=/api/backup/import-first-run; use_auth=0; fi
    response="$(mktemp /tmp/olc-backup-import-XXXXXX.json)"
    trap 'rm -f "$response"' EXIT
    request_import "$endpoint" "$in" "$missing" "$foreign" "$use_auth" >"$response"
    cat "$response"
    [[ "$missing" == "install" ]] && install_requested_components "$response"
    systemctl restart olcrtc-manager.service 2>/dev/null || true
    rm -f "$response"
    trap - EXIT
    log "import completed"
    ;;
  -h|--help) usage ;;
  *) usage; exit 1 ;;
esac
