#!/usr/bin/env bash
# Rotate active bridge window in bridges.conf when probes fail or Tor crashed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

# shellcheck source=tor-bridge-lib.sh
source "$SCRIPT_DIR/tor-bridge-lib.sh"

POOL_FILE="${POOL_FILE:-/var/lib/olcrtc/tor-bridges-pool.txt}"
BRIDGES_OUT="/etc/tor/bridges.conf"
IDX_FILE="/var/lib/olcrtc/bridge-rotation.idx"
WINDOW="${WINDOW:-${FAST_WINDOW:-8}}"
RESTART_TOR=1
POOL_GREP="$(bridge_pool_grep_pattern)"

[[ "${1:-}" == "--no-restart" ]] && RESTART_TOR=0

[[ -f "$POOL_FILE" ]] || FETCH_MAX_AGE_SEC=0 "$SCRIPT_DIR/tor-bridge-pool.sh" --fetch --no-restart 2>/dev/null || true
[[ -f "$POOL_FILE" ]] || { echo "no pool file" >&2; exit 1; }

pool=()
if [[ -f "$GOOD_BRIDGES" ]] && [[ -s "$GOOD_BRIDGES" ]]; then
  mapfile -t pool < <(grep -E "$POOL_GREP" "$GOOD_BRIDGES")
fi
if (( ${#pool[@]} < WINDOW )); then
  mapfile -t more < <(grep -E "$POOL_GREP" "$POOL_FILE")
  pool+=("${more[@]}")
fi
mapfile -t pool < <(printf '%s\n' "${pool[@]}" | awk '!seen[$0]++')
n="${#pool[@]}"
(( n > 0 )) || exit 1

idx=0
[[ -f "$IDX_FILE" ]] && idx="$(cat "$IDX_FILE")"
idx=$(((idx + 1) % n))
echo "$idx" >"$IDX_FILE"

active=()
for ((i = 0; i < WINDOW; i++)); do
  active+=("${pool[$(( (idx + i) % n ))]}")
done
merge_user_bridge_lines active

tmp="$(mktemp)"
write_active_bridges_conf "$tmp" "${active[@]}"
safety_check_output_path BRIDGES_OUT "$BRIDGES_OUT"
safety_install_file "$tmp" "$BRIDGES_OUT" 0644
rm -f "$tmp"

echo "rotated to offset $idx ($WINDOW bridges, types=$BRIDGE_TYPES)"
if [[ "$RESTART_TOR" -eq 1 ]]; then
  systemctl reset-failed tor@default 2>/dev/null || true
  systemctl restart tor@default
fi
