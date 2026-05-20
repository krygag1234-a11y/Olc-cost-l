#!/usr/bin/env bash
# Shared functions for Tor bridge pool (source, do not execute).
[[ -n "${_TOR_BRIDGE_LIB_LOADED:-}" ]] && return 0
_TOR_BRIDGE_LIB_LOADED=1

BRIDGES_RAW_URL="${BRIDGES_RAW_URL:-https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/TOR-BRIDGES/TOR_BRIDGES_ALL.txt}"
POOL_DIR="${POOL_DIR:-/var/lib/olcrtc}"
HEALTH_DB="${HEALTH_DB:-$POOL_DIR/tor-bridge-health.tsv}"

# Tor 0.4.8.10 ABRT on this bridge
BRIDGE_BLACKLIST_FP=(
  EDF46C5F723F323521075F7F8D7E534700D1019E
)

# webtunnel only by default (RU DPI); comma list: webtunnel,obfs4,vanilla
BRIDGE_TYPES="${BRIDGE_TYPES:-webtunnel}"

bridge_log() { echo "[$(date -Iseconds)] $*" | tee -a "${LOG_FILE:-/var/log/olcrtc-bridge-pool.log}"; }

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
  if [[ "$line" =~ ^webtunnel || "$line" =~ ^obfs4 ]]; then
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
  if [[ "$line" =~ ^Bridge[[:space:]]webtunnel || "$line" =~ ^Bridge[[:space:]]obfs4 ]]; then
    awk '{print $4}' <<<"$line"
  elif [[ "$line" =~ ^Bridge[[:space:]] ]]; then
    awk '{print $3}' <<<"$line"
  else
    awk '{print $(NF-1); print $4}' <<<"$line" 2>/dev/null | head -1
  fi
}

bridge_tunnel_url() {
  sed -n 's/.*url=\(https\?:\/\/[^ ]*\).*/\1/p' <<<"$1" | head -1
}

fetch_bridges_raw() {
  local dest="$1"
  curl -fsSL --max-time 120 "$BRIDGES_RAW_URL" -o "$dest"
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
  if [[ "$status" == "ok" || "$status" == "url_ok" ]]; then
    ok=$((ok + 1))
    streak=0
    last_ok=$now
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
    echo -e "${fp}\t${ok}\t${fail}\t${streak}\t${last_ok}\t${last_fail}\t${status}"
  } >"$tmp"
  install -m 0644 "$tmp" "$HEALTH_DB"
  rm -f "$tmp"
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
  local line ok fail streak
  line="$(grep -F "$fp" "$HEALTH_DB" 2>/dev/null | head -1)" || { echo 0; return; }
  IFS=$'\t' read -r _ ok fail streak _ <<<"$line"
  echo $((ok * 10 - fail * 3 - streak * 5))
}

probe_url() {
  local line="$1"
  local url host
  url="$(bridge_tunnel_url "$line")"
  if [[ -z "$url" ]]; then
    # vanilla/obfs4: TCP to bridge host
    local hostport
    hostport="$(sed -n 's/^Bridge[[:space:]]\+\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
    host="${hostport%%:*}"
    [[ -n "$host" ]] || return 1
    timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${hostport##*:}" 2>/dev/null && return 0
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
  {
    echo "# Active bridges — $(date -Iseconds)"
    echo "# Managed by /opt/olcrtc/scripts/tor-bridge-pool.sh"
    echo "UseBridges 1"
    if bridge_type_enabled webtunnel; then
      echo "ClientTransportPlugin webtunnel exec /usr/bin/webtunnel-client"
    fi
    if bridge_type_enabled obfs4; then
      echo "ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy"
    fi
  } >"$dest"
}
