#!/usr/bin/env bash
# Deep Tor bootstrap check for bridges (TorBridgePulse-style, no Postgres).
# Spawns a temporary tor per bridge, polls ControlPort bootstrap-phase.
#
# Usage:
#   tor-bridge-deep-check.sh --from-pool --limit 6
#   tor-bridge-deep-check.sh --bridge 'Bridge webtunnel ...'
#   tor-bridge-deep-check.sh --good-only --limit 4 --jobs 2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tor-bridge-lib.sh
source "$SCRIPT_DIR/tor-bridge-lib.sh"

LOG_FILE="${LOG_FILE:-/var/log/olcrtc-bridge-deep.log}"
LIMIT="${LIMIT:-6}"
JOBS="${JOBS:-2}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-90}"
FROM_POOL=0
GOOD_ONLY=0
SINGLE_BRIDGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-pool) FROM_POOL=1 ;;
    --good-only) GOOD_ONLY=1 ;;
    --limit) LIMIT="$2"; shift ;;
    --jobs) JOBS="$2"; shift ;;
    --timeout) BOOTSTRAP_TIMEOUT="$2"; shift ;;
    --bridge) SINGLE_BRIDGE="$2"; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
  shift
done

pick_free_port() {
  local p
  for _ in $(seq 1 40); do
    p=$((20000 + RANDOM % 15000))
    if ! timeout 0.2 bash -c "echo >/dev/tcp/127.0.0.1/$p" 2>/dev/null; then
      echo "$p"
      return 0
    fi
  done
  echo $((20000 + RANDOM % 15000))
}

ctp_lines_for_bridge() {
  local line="$1"
  if [[ "$line" == *" webtunnel "* ]]; then
    local wt="/usr/bin/webtunnel-client"
    [[ -x "$wt" ]] || wt="/usr/local/bin/webtunnel-client"
    echo "ClientTransportPlugin webtunnel exec $wt"
  elif [[ "$line" == *" obfs4 "* ]]; then
    echo "ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy"
  elif [[ "$line" == *" snowflake "* ]]; then
    echo "SKIP_SNOWFLAKE"
    return 1
  fi
  return 0
}

tor_control_bootstrap_progress() {
  local ctrl="$1" cookie="$2"
  local cookie_hex resp prog
  cookie_hex="$(xxd -ps "$cookie" 2>/dev/null | tr -d '\n')" || return 1
  resp="$(printf 'AUTHENTICATE %s\r\nGETINFO status/bootstrap-phase\r\nQUIT\r\n' "$cookie_hex" \
    | timeout 3 nc -w 2 127.0.0.1 "$ctrl" 2>/dev/null || true)"
  prog="$(sed -n 's/.*PROGRESS=\([0-9]*\).*/\1/p' <<<"$resp" | head -1)"
  echo "${prog:-0}"
}

deep_check_one() {
  local line="$1"
  local fp ctp tmp socks ctrl tpid i prog logf
  fp="$(bridge_fingerprint "$line")"
  ctp="$(ctp_lines_for_bridge "$line")" || {
    bridge_log "deep: skip unsupported PT ($fp)"
    health_record "$fp" "bootstrap_skip"
    return 1
  }

  tmp="$(mktemp -d /tmp/tor-deep.XXXXXX)"
  socks="$(pick_free_port)"
  ctrl=$((socks + 1))
  logf="$tmp/tor.log"

  {
    echo "ClientOnly 1"
    echo "UseBridges 1"
    echo "$ctp"
    echo "$line"
    echo "SocksPort $socks"
    echo "ControlPort $ctrl"
    echo "DataDirectory $tmp/data"
    echo "CookieAuthentication 1"
    echo "Log notice file $logf"
    echo "CircuitBuildTimeout $BOOTSTRAP_TIMEOUT"
    echo "LearnCircuitBuildTimeout 0"
    echo "FetchDirInfoEarly 0"
  } >"$tmp/torrc"

  tor -f "$tmp/torrc" >>"$logf" 2>&1 &
  tpid=$!

  cleanup() {
    kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$tmp"
  }
  trap cleanup RETURN

  local ok=0 cookie=""
  for ((i = 1; i <= BOOTSTRAP_TIMEOUT; i++)); do
    if [[ -f "$tmp/data/control_auth_cookie" ]]; then
      cookie="$tmp/data/control_auth_cookie"
      prog="$(tor_control_bootstrap_progress "$ctrl" "$cookie")"
      if [[ "$prog" -ge 100 ]]; then
        if curl -fsS --max-time 12 --socks5-hostname "127.0.0.1:$socks" \
          https://check.torproject.org/api/ip >/dev/null 2>&1; then
          ok=1
          break
        fi
      fi
    fi
    if ! kill -0 "$tpid" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  if [[ "$ok" -eq 1 ]]; then
    bridge_log "deep: OK $fp (${i}s)"
    health_record "$fp" "bootstrap_ok"
    record_good_bridge "$line"
    return 0
  fi
  bridge_log "deep: FAIL $fp progress=${prog:-0} (${i}s)"
  health_record "$fp" "bootstrap_fail"
  while IFS= read -r _l; do
    bridge_log "  $_l"
  done < <(tail -5 "$logf" 2>/dev/null || true)
  return 1
}

collect_candidates() {
  local -a lines=()
  if [[ -n "$SINGLE_BRIDGE" ]]; then
    lines=("$SINGLE_BRIDGE")
  elif [[ "$GOOD_ONLY" -eq 1 && -f "$GOOD_BRIDGES" ]]; then
    mapfile -t lines < <(grep -E '^Bridge ' "$GOOD_BRIDGES" | head -n "$LIMIT")
  elif [[ "$FROM_POOL" -eq 1 && -f "$POOL_FILE" ]]; then
    local -a scored=() line fp score
    mapfile -t pool < <(grep -E '^Bridge ' "$POOL_FILE")
    for line in "${pool[@]}"; do
      fp="$(bridge_fingerprint "$line")"
      bridge_is_blacklisted "$fp" && continue
      score="$(health_score "$fp")"
      if [[ "${OLCRTC_BRIDGE_IPV4_ONLY:-1}" == "1" ]] && bridge_is_ipv6_heavy "$line"; then
        score=$((score - 1000))
      fi
      scored+=("$score"$'\t'"$line")
    done
    mapfile -t lines < <(printf '%s\n' "${scored[@]}" | sort -t$'\t' -k1 -nr | head -n "$LIMIT" | cut -f2-)
  else
    echo "Specify --from-pool, --good-only, or --bridge" >&2
    exit 1
  fi
  printf '%s\n' "${lines[@]}"
}

main() {
  [[ "$(id -u)" -eq 0 ]] || { echo "root required" >&2; exit 1; }
  mkdir -p "$POOL_DIR"
  touch "$LOG_FILE"
  health_db_init

  mapfile -t candidates < <(collect_candidates)
  (( ${#candidates[@]} > 0 )) || { bridge_log "deep: no candidates"; exit 0; }

  bridge_log "deep: checking ${#candidates[@]} bridge(s) jobs=$JOBS timeout=${BOOTSTRAP_TIMEOUT}s"

  local running=0 ok=0 fail=0 st
  for line in "${candidates[@]}"; do
    while (( running >= JOBS )); do
      if wait -n 2>/dev/null; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
      running=$((running - 1))
    done
    deep_check_one "$line" &
    running=$((running + 1))
  done
  while (( running > 0 )); do
    if wait -n 2>/dev/null; then st=0; else st=$?; fi
    [[ "$st" -eq 0 ]] && ok=$((ok + 1)) || fail=$((fail + 1))
    running=$((running - 1))
  done

  bridge_log "deep: done ok=$ok fail=$fail"
}

main "$@"
