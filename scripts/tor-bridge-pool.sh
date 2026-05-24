#!/usr/bin/env bash
# Tor bridge pool: fetch TOR_BRIDGES_ALL.txt, health tracking, active bridges.conf
#
# Usage:
#   tor-bridge-pool.sh                 # fetch + probe + apply + restart tor
#   tor-bridge-pool.sh --monitor       # only probe + update health (cron)
#   tor-bridge-pool.sh --apply         # select from pool/health, write bridges.conf
#   tor-bridge-pool.sh --fetch         # only download/parse pool
#   tor-bridge-pool.sh --url-only      # fast TCP/URL probe (no tor bootstrap)
#   tor-bridge-pool.sh --types webtunnel,obfs4
#   tor-bridge-pool.sh --target 12     # min active bridges in torrc
#   tor-bridge-pool.sh --no-restart
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tor-bridge-lib.sh
source "$SCRIPT_DIR/tor-bridge-lib.sh"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

POOL_FILE="${POOL_FILE:-$POOL_DIR/tor-bridges-pool.txt}"
BRIDGES_OUT="${BRIDGES_OUT:-/etc/tor/bridges.conf}"
TORRC="${TORRC:-/etc/tor/torrc}"
safety_check_output_path POOL_FILE "$POOL_FILE"
safety_check_output_path BRIDGES_OUT "$BRIDGES_OUT"
safety_check_output_path TORRC "$TORRC"
[[ "$TORRC" == /etc/tor/torrc ]] || { echo "REFUSE TORRC=$TORRC" >&2; exit 1; }
LOG_FILE="${LOG_FILE:-/var/log/olcrtc-bridge-pool.log}"

TARGET_ACTIVE="${TARGET_ACTIVE:-12}"
MAX_ACTIVE="${MAX_ACTIVE:-18}"
MIN_POOL_CANDIDATES="${MIN_POOL_CANDIDATES:-40}"
PARALLEL_JOBS="${PARALLEL_JOBS:-6}"
MODE_PROBE="url-only"
RESTART_TOR=1
DO_FETCH=1
DO_PROBE=1
DO_APPLY=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --monitor) DO_FETCH=0; DO_APPLY=0 ;;
    --fast) DO_FETCH=0; MODE_PROBE="skip"; DO_PROBE=0; DO_APPLY=1 ;;
    --apply) DO_FETCH=0; DO_PROBE=0 ;;
    --fetch) DO_PROBE=0; DO_APPLY=0 ;;
    --url-only) MODE_PROBE="url-only" ;;
    --full-tor) MODE_PROBE="full" ;;
    --no-restart) RESTART_TOR=0 ;;
    --jobs) PARALLEL_JOBS="$2"; shift ;;
    --target) TARGET_ACTIVE="$2"; shift ;;
    --max) MAX_ACTIVE="$2"; shift ;;
    --types) BRIDGE_TYPES="$2"; shift ;;
    -h|--help)
      grep '^#' "$0" | head -20
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
  shift
done

fetch_and_merge_pool() {
  if pool_is_fresh; then
    bridge_log "pool fresh (<${FETCH_MAX_AGE_SEC}s), skip download"
    trim_pool_file
    return 0
  fi
  local raw tmp merged
  raw="$(mktemp)"
  tmp="$(mktemp)"
  merged="$(mktemp)"
  bridge_log "fetch $BRIDGES_RAW_URL"
  fetch_bridges_raw "$raw"
  parse_bridges_file "$raw" "$tmp"
  rm -f "$raw"
  bridge_log "parsed $(wc -l <"$tmp") bridges (types=$BRIDGE_TYPES)"

  # merge with existing pool (keep history)
  {
    [[ -f "$POOL_FILE" ]] && grep -E '^Bridge ' "$POOL_FILE" 2>/dev/null || true
    cat "$tmp"
  } | awk '!seen[$0]++' >"$merged"
  rm -f "$tmp"

  local count
  count="$(wc -l <"$merged")"
  if ((count < MIN_POOL_CANDIDATES)); then
    bridge_log "WARN: pool has only $count candidates (want $MIN_POOL_CANDIDATES)"
  fi
  {
    echo "# pool $(date -Iseconds)"
    echo "# source: $BRIDGES_RAW_URL"
    cat "$merged"
  } >"$POOL_FILE"
  bridge_log "pool file: $count lines → $POOL_FILE"
  trim_pool_file
}

probe_pool_parallel() {
  [[ "$MODE_PROBE" != "skip" ]] || { bridge_log "probe skipped"; return 0; }
  local -a lines=()
  local active_conf="${BRIDGES_OUT:-/etc/tor/bridges.conf}"
  if [[ -f "$active_conf" ]]; then
    mapfile -t active < <(grep -E '^Bridge ' "$active_conf")
    lines+=("${active[@]}")
  fi
  if [[ -f "$GOOD_BRIDGES" ]]; then
    mapfile -t good < <(grep -E '^Bridge ' "$GOOD_BRIDGES")
    lines+=("${good[@]}")
  fi
  mapfile -t pool < <(grep -E '^Bridge ' "$POOL_FILE")
  # Top health scores first, then fill probe budget
  local -a scored=() line fp score
  for line in "${pool[@]}"; do
    fp="$(bridge_fingerprint "$line")"
    score="$(health_score "$fp")"
    scored+=("$score"$'\t'"$line")
  done
  mapfile -t ranked < <(printf '%s\n' "${scored[@]}" | sort -t$'\t' -k1 -nr | head -n "$((MAX_PROBE * 2))" | cut -f2-)
  lines+=("${ranked[@]}")
  # dedupe, cap
  mapfile -t lines < <(printf '%s\n' "${lines[@]}" | awk '!seen[$0]++' | head -n "$MAX_PROBE")
  local n="${#lines[@]}"
  ((n > 0)) || return 0
  bridge_log "probing $n bridges (mode=$MODE_PROBE jobs=$PARALLEL_JOBS max=$MAX_PROBE)"

  local results_dir i running=0
  results_dir="$(mktemp -d)"

  probe_one() {
    local idx="$1" line="$2"
    local fp status
    fp="$(bridge_fingerprint "$line")"
    if probe_url "$line"; then
      status="url_ok"
      health_record "$fp" "url_ok"
      record_good_bridge "$line"
    else
      status="fail"
      health_record "$fp" "fail"
    fi
    echo -e "${fp}\t${status}\t${line}" >"$results_dir/$idx"
  }

  for ((i = 0; i < n; i++)); do
    while ((running >= PARALLEL_JOBS)); do
      wait -n 2>/dev/null || wait
      running=$((running - 1))
    done
    probe_one "$i" "${lines[$i]}" &
    running=$((running + 1))
  done
  wait
  rm -rf "$results_dir"
}

select_active_bridges() {
  mapfile -t candidates < <(grep -E '^Bridge ' "$POOL_FILE")
  local -a scored=()
  local line fp score drop
  for line in "${candidates[@]}"; do
    fp="$(bridge_fingerprint "$line")"
    bridge_is_blacklisted "$fp" && continue
    drop=0
    health_should_drop "$fp" && drop=1
    score="$(health_score "$fp")"
    if [[ "${OLCRTC_BRIDGE_IPV4_ONLY:-1}" == "1" ]] && bridge_is_ipv6_heavy "$line"; then
      score=$((score - 1000))
    fi
    if [[ "$drop" -eq 1 && "$score" -lt 20 ]]; then
      continue
    fi
    scored+=("$score"$'\t'"$line")
  done

  # sort by score desc
  mapfile -t sorted < <(printf '%s\n' "${scored[@]}" | sort -t$'\t' -k1 -nr)
  local -a active=()
  local entry s
  for entry in "${sorted[@]}"; do
    line="${entry#*$'\t'}"
    [[ -n "$line" ]] || continue
    # prefer recent url_ok in last probe — skip if fail_streak high unless need fill
    active+=("$line")
    [[ ${#active[@]} -ge $MAX_ACTIVE ]] && break
  done

  # fill up to TARGET from pool even if low score
  if (( ${#active[@]} < TARGET_ACTIVE )); then
    for line in "${candidates[@]}"; do
      fp="$(bridge_fingerprint "$line")"
      bridge_is_blacklisted "$fp" && continue
      health_should_drop "$fp" && continue
      local found=0
      for a in "${active[@]}"; do [[ "$a" == "$line" ]] && found=1; done
      [[ $found -eq 1 ]] && continue
      active+=("$line")
      [[ ${#active[@]} -ge $TARGET_ACTIVE ]] && break
    done
  fi

  # When multiple PTs enabled, keep a minimum of webtunnel (RU DPI primary path).
  if [[ ",${BRIDGE_TYPES}," == *",webtunnel,"* ]] && [[ ",${BRIDGE_TYPES}," == *",obfs4,"* ]]; then
    local min_wt="${MIN_WEBTUNNEL_ACTIVE:-6}" wt_count=0 line_wt fp_wt found_wt
    for line_wt in "${active[@]}"; do [[ "$line_wt" == *" webtunnel "* ]] && wt_count=$((wt_count + 1)); done
    if (( wt_count < min_wt )); then
      local wt_allow_v6=0 has_v4_wt=0
      if grep -E '^Bridge webtunnel ' "$POOL_FILE" 2>/dev/null | grep -qv '\['; then
        has_v4_wt=1
      fi
      if [[ "$has_v4_wt" -eq 0 ]] && [[ "${OLCRTC_BRIDGE_IPV4_ONLY:-1}" == "1" ]]; then
        bridge_log "skip min webtunnel (no IPv4 webtunnel; obfs4-first)"
        min_wt=0
        wt_count="$min_wt"
      fi
      if (( wt_count < min_wt )); then
        if ! grep -E '^Bridge webtunnel ' "$POOL_FILE" 2>/dev/null | grep -qv '\['; then
          wt_allow_v6=1
        fi
        mapfile -t wt_fill < <(pick_webtunnel_pool_lines "$((min_wt * 4))")
      for line_wt in "${wt_fill[@]}"; do
        if [[ "${OLCRTC_BRIDGE_IPV4_ONLY:-1}" == "1" ]] && [[ "$wt_allow_v6" -eq 0 ]] && bridge_is_ipv6_heavy "$line_wt"; then
          continue
        fi
        fp_wt="$(bridge_fingerprint "$line_wt")"
        bridge_is_blacklisted "$fp_wt" && continue
        health_should_drop "$fp_wt" && continue
        found_wt=0
        for a in "${active[@]}"; do [[ "$a" == "$line_wt" ]] && found_wt=1; done
        [[ $found_wt -eq 1 ]] && continue
        active=("$line_wt" "${active[@]}")
        wt_count=$((wt_count + 1))
        [[ ${#active[@]} -ge $MAX_ACTIVE ]] && active=("${active[@]:0:$MAX_ACTIVE}")
        (( wt_count >= min_wt )) && break
      done
      fi
    fi
  fi

  merge_user_bridge_lines active
  reorder_bridges_for_speed active

  if (( ${#active[@]} == 0 )); then
    bridge_log "ERROR: no bridges to activate"
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  write_active_bridges_conf "$tmp" "${active[@]}"
  if [[ -f "$BRIDGES_OUT" ]] && cmp -s "$tmp" "$BRIDGES_OUT"; then
    bridge_log "bridges.conf unchanged (${#active[@]} bridges)"
    rm -f "$tmp"
    # No need to rotate/restart Tor when active set is the same.
    return 0
  fi
  safety_install_file "$tmp" "$BRIDGES_OUT" 0644
  rm -f "$tmp"
  safety_torrc_include_bridges "$TORRC"
  bridge_log "wrote $BRIDGES_OUT (${#active[@]} bridges, target=$TARGET_ACTIVE)"
  return 0
}

restart_tor_if_needed() {
  [[ "$RESTART_TOR" -eq 1 ]] || return 0
  systemctl reset-failed tor@default 2>/dev/null || true
  systemctl restart tor@default
  for i in $(seq 1 25); do
    if curl -fsS --max-time 3 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip >/dev/null 2>&1; then
      bridge_log "Tor SOCKS ready (${i}s)"
      return 0
    fi
    sleep 1
  done
  bridge_log "WARN: Tor not ready after restart — try tor-bridge-rotate.sh"
}

main() {
  [[ "$(id -u)" -eq 0 ]] || { echo "root required" >&2; exit 1; }
  mkdir -p "$POOL_DIR"
  touch "$LOG_FILE"
  health_db_init

  (( DO_FETCH )) && fetch_and_merge_pool
  [[ -f "$POOL_FILE" ]] || { bridge_log "no pool file"; fetch_and_merge_pool || true; }
  [[ -f "$POOL_FILE" ]] || { bridge_log "no pool file"; exit 1; }

  (( DO_PROBE )) && probe_pool_parallel
  if (( DO_APPLY )); then
    if select_active_bridges; then
      restart_tor_if_needed
    else
      if [[ "$RESTART_TOR" -eq 1 ]]; then
        FAST_WINDOW="${FAST_WINDOW:-6}" "$SCRIPT_DIR/tor-bridge-rotate.sh" 2>/dev/null || true
        restart_tor_if_needed
      else
        FAST_WINDOW="${FAST_WINDOW:-6}" "$SCRIPT_DIR/tor-bridge-rotate.sh" --no-restart 2>/dev/null || true
      fi
    fi
  fi
  bridge_log "done"
}

main "$@"
