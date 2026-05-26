#!/usr/bin/env bash
# Shared functions for Tor bridge pool (source, do not execute).
[[ -n "${_TOR_BRIDGE_LIB_LOADED:-}" ]] && return 0
_TOR_BRIDGE_LIB_LOADED=1

BRIDGES_RAW_URL="${BRIDGES_RAW_URL:-https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/TOR-BRIDGES/TOR_BRIDGES_ALL.txt}"
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-webtunnel-build.sh
[[ -f "$_lib_dir/lib-webtunnel-build.sh" ]] && source "$_lib_dir/lib-webtunnel-build.sh"
OLC_REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$_lib_dir/.." && pwd)}"
BRIDGES_EXTRA_URLS_FILE="${BRIDGES_EXTRA_URLS_FILE:-$OLC_REPO_ROOT/data/bridge-extra-urls.txt}"
# Extra pools: env BRIDGES_EXTRA_URLS and/or data/bridge-extra-urls.txt
BRIDGES_EXTRA_URLS="${BRIDGES_EXTRA_URLS:-}"
POOL_DIR="${POOL_DIR:-/var/lib/olcrtc}"
POOL_FILE="${POOL_FILE:-$POOL_DIR/tor-bridges-pool.txt}"
GOOD_BRIDGES="${GOOD_BRIDGES:-$POOL_DIR/tor-bridges-good.txt}"
HEALTH_DB="${HEALTH_DB:-$POOL_DIR/tor-bridge-health.tsv}"
FETCH_MAX_AGE_SEC="${FETCH_MAX_AGE_SEC:-14400}"
MAX_POOL_LINES="${MAX_POOL_LINES:-500}"
MAX_PROBE="${MAX_PROBE:-72}"

# Tor 0.4.8.10 ABRT on this bridge
BRIDGE_BLACKLIST_FP=(
  EDF46C5F723F323521075F7F8D7E534700D1019E
)

# RU VPS: webtunnel + obfs4; optional snowflake (fallback line), vanilla
BRIDGE_TYPES="${BRIDGE_TYPES:-webtunnel,obfs4}"
USER_BRIDGES_FILE="${USER_BRIDGES_FILE:-/var/lib/olcrtc/tor-user-bridges.txt}"
OLCRTC_BRIDGE_IPV4_ONLY="${OLCRTC_BRIDGE_IPV4_ONLY:-1}"

bridge_log() {
  echo "[$(date -Iseconds)] $*" >>"${LOG_FILE:-/var/log/olcrtc-bridge-pool.log}"
}

bridge_is_blacklisted() {
  local fp="$1"
  for b in "${BRIDGE_BLACKLIST_FP[@]}"; do
    [[ "$fp" == "$b" ]] && return 0
  done
  return 1
}

# Returns 0 if line is a valid bridge definition (not comment/header/vless/etc.)
bridge_line_valid() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && return 1
  [[ "$line" == \#* ]] && return 1
  [[ "$line" == *"://"* && "$line" != webtunnel* && "$line" != obfs4* ]] && return 1
  [[ "$line" == vless://* || "$line" == trojan://* || "$line" == ss://* ]] && return 1

  if [[ "$line" =~ ^webtunnel[[:space:]] ]]; then
    bridge_type_enabled webtunnel || return 1
    return 0
  fi
  if [[ "$line" =~ ^obfs4[[:space:]] ]]; then
    bridge_type_enabled obfs4 || return 1
    return 0
  fi
  if [[ "$line" =~ ^snowflake([[:space:]]|$) ]]; then
    bridge_type_enabled snowflake || return 1
    return 0
  fi
  if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+[[:space:]]+[0-9A-Fa-f]{40} ]]; then
    bridge_type_enabled vanilla || return 1
    return 0
  fi
  return 1
}

bridge_type_enabled() {
  local t="$1"
  [[ ",${BRIDGE_TYPES}," == *",all,"* ]] && return 0
  [[ ",${BRIDGE_TYPES}," == *",$t,"* ]] && return 0
  return 1
}

# Normalize to torrc "Bridge ..." line
bridge_to_torrc() {
  local line="$1"
  if [[ "$line" =~ ^Bridge[[:space:]] ]]; then
    echo "$line"
    return 0
  fi
  if [[ "$line" =~ ^webtunnel || "$line" =~ ^obfs4 || "$line" =~ ^snowflake ]]; then
    echo "Bridge $line"
    return 0
  fi
  if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+ ]]; then
    echo "Bridge $line"
    return 0
  fi
  return 1
}

bridge_fingerprint() {
  local line="$1"
  if [[ "$line" =~ ^Bridge[[:space:]]snowflake ]]; then
    echo "snowflake-fallback"
  elif [[ "$line" =~ ^Bridge[[:space:]]webtunnel || "$line" =~ ^Bridge[[:space:]]obfs4 ]]; then
    awk '{print $4}' <<<"$line"
  elif [[ "$line" =~ ^Bridge[[:space:]] ]]; then
    awk '{print $3}' <<<"$line"
  else
    awk '{print $(NF-1); print $4}' <<<"$line" 2>/dev/null | head -1
  fi
}

bridge_is_ipv6_heavy() {
  local line="$1"
  # webtunnel uses url= HTTPS endpoint; bracket IPv6 in bridgeline is not the dial target
  if [[ "$line" == *" webtunnel "* ]] && [[ "$line" == *"url="* ]]; then
    return 1
  fi
  [[ "$line" == *"["* ]] && return 0
  [[ "$line" =~ [0-9a-fA-F]{2,}:[0-9a-fA-F]{2,}: ]] && return 0
  return 1
}

bridge_probe_hostport() {
  local line="$1"
  awk '{
    for (i = 1; i <= NF; i++)
      if ($i ~ /^(\[?[0-9a-fA-F:.]+\]?):[0-9]+$/) { print $i; exit }
  }' <<<"$line"
}

bridge_pool_grep_pattern() {
  if [[ ",${BRIDGE_TYPES}," == *",all,"* ]]; then
    echo '^Bridge '
    return
  fi
  local pat="" t
  IFS=',' read -r -a _bt <<<"${BRIDGE_TYPES}"
  for t in "${_bt[@]}"; do
    t="${t// /}"
    [[ -n "$t" ]] || continue
    pat+="|${t}"
  done
  [[ -n "$pat" ]] || { echo '^Bridge webtunnel '; return; }
  echo "^Bridge (${pat#|}) "
}

load_bridges_extra_urls() {
  local -a urls=()
  if [[ -n "${BRIDGES_EXTRA_URLS:-}" ]]; then
    IFS=',' read -r -a urls <<<"${BRIDGES_EXTRA_URLS// /}"
  fi
  if [[ -f "$BRIDGES_EXTRA_URLS_FILE" ]]; then
    local u
    while IFS= read -r u || [[ -n "$u" ]]; do
      u="${u%%#*}"
      u="${u// /}"
      [[ -n "$u" ]] && urls+=("$u")
    done <"$BRIDGES_EXTRA_URLS_FILE"
  fi
  if ((${#urls[@]} == 0)); then
    urls=(
      "https://raw.githubusercontent.com/Delta-Kronecker/Tor-Bridges-Collector/main/bridge/webtunnel_tested.txt"
      "https://raw.githubusercontent.com/Delta-Kronecker/Tor-Bridges-Collector/main/bridge/obfs4_tested.txt"
    )
  fi
  BRIDGES_EXTRA_URLS="$(printf '%s,' "${urls[@]}" | sed 's/,$//')"
}

merge_user_bridge_lines() {
  local -n _out=$1
  [[ -f "$USER_BRIDGES_FILE" ]] || return 0
  local line torline fp found
  while IFS= read -r line || [[ -n "$line" ]]; do
    bridge_line_valid "$line" || continue
    torline="$(bridge_to_torrc "$line")" || continue
    fp="$(bridge_fingerprint "$torline")"
    bridge_is_blacklisted "$fp" && continue
    found=0
    for a in "${_out[@]}"; do [[ "$a" == "$torline" ]] && found=1; done
    [[ $found -eq 1 ]] && continue
    _out+=("$torline")
  done <"$USER_BRIDGES_FILE"
}

snowflake_client_path() {
  command -v snowflake-client 2>/dev/null || echo /usr/bin/snowflake-client
}

# Tor tries bridges top-to-bottom: webtunnel (faster) before obfs4 (fallback).
pick_webtunnel_pool_lines() {
  local n="${1:-24}"
  local -a v4=()
  mapfile -t v4 < <(grep -E '^Bridge webtunnel ' "$POOL_FILE" 2>/dev/null | grep -v '\[' || true)
  if ((${#v4[@]} > 0)); then
    printf '%s\n' "${v4[@]}" | awk '!seen[$0]++' | head -n "$n"
    return
  fi
  # url= webtunnel: connect via HTTPS host, not bridgeline IPv6 placeholder
  mapfile -t urlwt < <(grep -E '^Bridge webtunnel ' "$POOL_FILE" 2>/dev/null | grep ' url=' || true)
  if ((${#urlwt[@]} > 0)); then
    bridge_log "webtunnel pool: ${#urlwt[@]} with url= (IPv4 VPS OK)"
    printf '%s\n' "${urlwt[@]}" | awk '!seen[$0]++' | head -n "$n"
    return
  fi
  if [[ "${OLCRTC_BRIDGE_IPV4_ONLY:-1}" == "1" ]]; then
    bridge_log "WARN: no IPv4 webtunnel in pool — skip webtunnel (obfs4/snowflake only)"
    return 0
  fi
  bridge_log "WARN: no IPv4 webtunnel in pool — using IPv6 webtunnel fallback"
  grep -E '^Bridge webtunnel ' "$POOL_FILE" 2>/dev/null | awk '!seen[$0]++' | head -n "$n" || true
}

reorder_bridges_for_speed() {
  local -n _lines=$1
  local -a wt=() ob=() other=() scored=() line fp score
  for line in "${_lines[@]}"; do
    fp="$(bridge_fingerprint "$line")"
    score="$(health_score "$fp")"
    if [[ "$line" == *" webtunnel "* ]]; then
      wt+=("$score"$'\t'"$line")
    elif [[ "$line" == *" obfs4 "* ]]; then
      ob+=("$score"$'\t'"$line")
    else
      other+=("$line")
    fi
  done
  _lines=()
  if ((${#wt[@]})); then
    mapfile -t scored < <(printf '%s\n' "${wt[@]}" | sort -t$'\t' -k1 -nr | cut -f2-)
    _lines+=("${scored[@]}")
  fi
  if ((${#ob[@]})); then
    mapfile -t scored < <(printf '%s\n' "${ob[@]}" | sort -t$'\t' -k1 -nr | cut -f2-)
    _lines+=("${scored[@]}")
  fi
  _lines+=("${other[@]}")
}

append_snowflake_fallback_line() {
  local -n _arr=$1
  # VPS probe 2026-05-23: snowflake-only bootstrap stuck at 10% (client exit 512).
  [[ -f "${POOL_DIR}/tor-snowflake-viable" ]] || return 0
  [[ "${OLCRTC_TOR_SNOWFLAKE_FALLBACK:-0}" == "1" ]] || bridge_type_enabled snowflake || return 0
  [[ -x "$(snowflake_client_path)" ]] || return 0
  local line="Bridge snowflake 192.0.2.3:80"
  local a
  for a in "${_arr[@]}"; do [[ "$a" == "$line" ]] && return 0; done
  _arr+=("$line")
}

bridge_tunnel_url() {
  sed -n 's/.*url=\(https\?:\/\/[^ ]*\).*/\1/p' <<<"$1" | head -1
}

pool_is_fresh() {
  [[ -f "$POOL_FILE" ]] || return 1
  local age now mtime
  now="$(date +%s)"
  mtime="$(stat -c %Y "$POOL_FILE" 2>/dev/null || echo 0)"
  age=$((now - mtime))
  [[ "$age" -lt "$FETCH_MAX_AGE_SEC" ]]
}

fetch_bridges_raw() {
  local dest="$1"
  local tmp merged url
  load_bridges_extra_urls
  tmp="$(mktemp)"
  merged="$(mktemp)"
  curl -fsSL --max-time 120 "$BRIDGES_RAW_URL" -o "$tmp"
  cp "$tmp" "$merged"
  if [[ -n "${BRIDGES_EXTRA_URLS:-}" ]]; then
    IFS=',' read -r -a _extra <<<"${BRIDGES_EXTRA_URLS}"
    for url in "${_extra[@]}"; do
      [[ -n "$url" ]] || continue
      if curl -fsSL --max-time 90 "$url" -o "$tmp" 2>/dev/null; then
        cat "$tmp" >>"$merged"
        bridge_log "merged extra pool: $url"
      else
        bridge_log "WARN: skip extra pool $url"
      fi
    done
  fi
  mv "$merged" "$dest"
  rm -f "$tmp"
}

trim_pool_file() {
  [[ -f "$POOL_FILE" ]] || return 0
  local n
  n="$(grep -cE '^Bridge ' "$POOL_FILE" 2>/dev/null || echo 0)"
  ((n <= MAX_POOL_LINES)) && return 0
  bridge_log "trim pool $n → $MAX_POOL_LINES lines"
  local tmp scored line fp score
  tmp="$(mktemp)"
  mapfile -t lines < <(grep -E '^Bridge ' "$POOL_FILE")
  scored=()
  for line in "${lines[@]}"; do
    fp="$(bridge_fingerprint "$line")"
    score="$(health_score "$fp")"
    scored+=("$score"$'\t'"$line")
  done
  {
    head -2 "$POOL_FILE" 2>/dev/null || true
    printf '%s\n' "${scored[@]}" | sort -t$'\t' -k1 -nr | head -n "$MAX_POOL_LINES" | cut -f2-
  } >"$tmp"
  install -m 0644 "$tmp" "$POOL_FILE"
  rm -f "$tmp"
}

record_good_bridge() {
  local line="$1"
  local lock="${GOOD_BRIDGES}.lock"
  [[ -f "$GOOD_BRIDGES" ]] || touch "$GOOD_BRIDGES"
  # Concurrent probes can call this in parallel — guard with a lock + unique tmp files.
  (
    flock -w 2 9 || exit 0
    grep -qxF "$line" "$GOOD_BRIDGES" 2>/dev/null || echo "$line" >>"$GOOD_BRIDGES"
    local tmp
    tmp="$(mktemp "${GOOD_BRIDGES}.tmp.XXXXXX")"
    awk '!seen[$0]++' "$GOOD_BRIDGES" >"$tmp" && mv "$tmp" "$GOOD_BRIDGES"
    tmp="$(mktemp "${GOOD_BRIDGES}.tmp.XXXXXX")"
    tail -n 120 "$GOOD_BRIDGES" >"$tmp" && mv "$tmp" "$GOOD_BRIDGES"
  ) 9>"$lock"
}

parse_bridges_file() {
  local src="$1" dest="$2"
  : >"$dest"
  while IFS= read -r line || [[ -n "$line" ]]; do
    bridge_line_valid "$line" || continue
    torline="$(bridge_to_torrc "$line")" || continue
    fp="$(bridge_fingerprint "$torline")"
    [[ -n "$fp" ]] || continue
    bridge_is_blacklisted "$fp" && continue
    echo "$torline"
  done <"$src" | awk '!seen[$0]++' >>"$dest"
}

health_db_init() {
  mkdir -p "$POOL_DIR"
  if [[ ! -f "$HEALTH_DB" ]]; then
    echo -e "fingerprint\tok_total\tfail_total\tfail_streak\tlast_ok\tlast_fail\tlast_status" >"$HEALTH_DB"
  fi
}

health_record() {
  local fp="$1" status="$2" # ok | fail | url_ok
  local now
  now="$(date +%s)"
  health_db_init
  local ok=0 fail=0 streak=0 last_ok=0 last_fail=0
  if line="$(grep -F "$fp" "$HEALTH_DB" 2>/dev/null | head -1)"; then
    IFS=$'\t' read -r _ ok fail streak last_ok last_fail _ <<<"$line"
  fi
  local record_status="$status"
  if [[ "$status" == "ok" || "$status" == "url_ok" ]]; then
    ok=$((ok + 1))
    streak=0
    last_ok=$now
    # Light probes must not erase a successful deep bootstrap result.
    if [[ "$status" == "url_ok" && "${last_status:-}" == "bootstrap_ok" ]]; then
      record_status="bootstrap_ok"
    fi
  else
    fail=$((fail + 1))
    streak=$((streak + 1))
    last_fail=$now
  fi
  local tmp
  tmp="$(mktemp)"
  {
    echo -e "fingerprint\tok_total\tfail_total\tfail_streak\tlast_ok\tlast_fail\tlast_status"
    grep -v -F "$fp" "$HEALTH_DB" 2>/dev/null | grep -v '^fingerprint' || true
    echo -e "${fp}\t${ok}\t${fail}\t${streak}\t${last_ok}\t${last_fail}\t${record_status}"
  } >"$tmp"
  mv "$tmp" "$HEALTH_DB"
  chmod 0644 "$HEALTH_DB"
}

# 0 = should keep (not enough failures / recent success)
health_should_drop() {
  local fp="$1"
  local drop_streak="${DROP_FAIL_STREAK:-8}"
  local grace_sec="${DROP_GRACE_SEC:-21600}" # 6h since last ok → still keep if newer
  local line ok fail streak last_ok last_fail
  line="$(grep -F "$fp" "$HEALTH_DB" 2>/dev/null | head -1)" || return 1
  IFS=$'\t' read -r _ ok fail streak last_ok last_fail _ <<<"$line"
  [[ "$streak" -lt "$drop_streak" ]] && return 1
  local now age
  now="$(date +%s)"
  if [[ "$last_ok" -gt 0 ]]; then
    age=$((now - last_ok))
    [[ "$age" -lt "$grace_sec" ]] && return 1
  fi
  return 0
}

health_score() {
  local fp="$1"
  local line ok fail streak last_status
  line="$(grep -F "$fp" "$HEALTH_DB" 2>/dev/null | head -1)" || { echo 0; return; }
  IFS=$'\t' read -r _ ok fail streak _ _ last_status <<<"$line"
  local bonus=0
  [[ "${last_status:-}" == "bootstrap_ok" ]] && bonus=50
  [[ "${last_status:-}" == "bootstrap_fail" ]] && bonus=-30
  echo $((ok * 10 - fail * 3 - streak * 5 + bonus))
}

probe_url() {
  local line="$1"
  local url host
  url="$(bridge_tunnel_url "$line")"
  if [[ -z "$url" ]]; then
    local hostport host port
    [[ "$line" == *" snowflake "* ]] && return 0
    hostport="$(bridge_probe_hostport "$line")"
    [[ -n "$hostport" ]] || return 1
    host="${hostport%%:*}"
    port="${hostport##*:}"
    host="${host#[}"
    host="${host%]}"
    [[ -n "$host" && -n "$port" ]] || return 1
    timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null && return 0
    return 1
  fi
  host="$(sed -E 's|https?://([^/:]+).*|\1|' <<<"$url")"
  timeout 5 bash -c "exec 3<>/dev/tcp/${host}/443" 2>/dev/null && return 0
  local code="000"
  code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time "${URL_TEST_TIMEOUT:-8}" -A Mozilla/5.0 -k "$url" 2>/dev/null)" || code="000"
  [[ "$code" =~ ^[23][0-9][0-9]$ ]] && return 0
  [[ "$code" != "000" ]] && [[ "$code" -lt 500 ]] 2>/dev/null && return 0
  return 1
}

write_torrc_header() {
  local dest="$1"
  shift
  local -a lines=("$@")
  local need_wt=0 need_obfs4=0 need_snow=0 line wt_bin
  if ((${#lines[@]} == 0)); then
    bridge_type_enabled webtunnel && need_wt=1
    bridge_type_enabled obfs4 && need_obfs4=1
    bridge_type_enabled snowflake && need_snow=1
  else
    for line in "${lines[@]}"; do
      [[ "$line" == *" webtunnel "* ]] && need_wt=1
      [[ "$line" == *" obfs4 "* ]] && need_obfs4=1
      [[ "$line" == *" snowflake "* ]] && need_snow=1
    done
  fi
  [[ -f "${POOL_DIR}/tor-snowflake-viable" ]] && [[ "${OLCRTC_TOR_SNOWFLAKE_FALLBACK:-0}" == "1" ]] && need_snow=1
  {
    echo "# Active bridges — $(date -Iseconds)"
    echo "# Managed by Olc-cost-l tor-bridge-pool.sh"
    echo "UseBridges 1"
    if (( need_wt )); then
      wt_bin="/usr/bin/webtunnel-client"
      [[ -x "$wt_bin" ]] || wt_bin="/usr/local/bin/webtunnel-client"
      if [[ -x "$wt_bin" ]]; then
        echo "ClientTransportPlugin webtunnel exec $wt_bin"
      fi
    fi
    if (( need_obfs4 )) && [[ -x /usr/bin/obfs4proxy ]]; then
      echo "ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy"
    fi
    if (( need_snow )) && [[ -x "$(snowflake_client_path)" ]]; then
      echo "ClientTransportPlugin snowflake exec $(snowflake_client_path)"
    fi
  } >"$dest"
}

write_active_bridges_conf() {
  local dest="$1"
  shift
  local -a active=("$@")
  append_snowflake_fallback_line active
  local tmp
  tmp="$(mktemp)"
  write_torrc_header "$tmp" "${active[@]}"
  printf '%s\n' "${active[@]}" >>"$tmp"
  mv "$tmp" "$dest"
}
