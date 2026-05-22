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

[[ "${1:-}" == "--no-restart" ]] && RESTART_TOR=0

[[ -f "$POOL_FILE" ]] || FETCH_MAX_AGE_SEC=0 "$SCRIPT_DIR/tor-bridge-pool.sh" --fetch --no-restart 2>/dev/null || true
[[ -f "$POOL_FILE" ]] || { echo "no pool file" >&2; exit 1; }

pool=()
if [[ -f "$GOOD_BRIDGES" ]] && [[ -s "$GOOD_BRIDGES" ]]; then
  mapfile -t pool < <(grep -E '^Bridge webtunnel ' "$GOOD_BRIDGES")
fi
if (( ${#pool[@]} < WINDOW )); then
  mapfile -t more < <(grep -E '^Bridge webtunnel ' "$POOL_FILE")
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

tmp="$(mktemp)"
{
  echo "# Rotated $(date -Iseconds) offset=$idx window=$WINDOW"
  echo "UseBridges 1"
  echo "ClientTransportPlugin webtunnel exec /usr/bin/webtunnel-client"
  printf '%s\n' "${active[@]}"
} >"$tmp"
safety_check_output_path BRIDGES_OUT "$BRIDGES_OUT"
safety_install_file "$tmp" "$BRIDGES_OUT" 0644
rm -f "$tmp"

echo "rotated to offset $idx ($WINDOW bridges)"
if [[ "$RESTART_TOR" -eq 1 ]]; then
  systemctl reset-failed tor@default 2>/dev/null || true
  systemctl restart tor@default
fi
