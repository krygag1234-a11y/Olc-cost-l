#!/usr/bin/env bash
# Flat hostnames for zapret (no suffix:/exact: prefixes).
set -euo pipefail
OUT="${ZAPRET_HOSTLIST:-/var/lib/olcrtc/zapret-direct-hostlist.txt}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

flatten() {
  [[ -f "$1" ]] || return 0
  sed -E 's/^#.*//;s/^[[:space:]]+//;s/[[:space:]]+$//;s/^exact://;s/^suffix:\.?//' "$1" |
    grep -E '^[a-z0-9.*-]+' | tr '[:upper:]' '[:lower:]'
}

{
  echo "# olcrtc zapret hostlist (RF-blocked only) — $(date -Iseconds)"
  flatten /var/lib/olcrtc/ru-blocked-tor-domains.txt
} | awk 'NF && !seen[$0]++' >"$TMP"

install -m 0644 "$TMP" "$OUT"
echo "[sync-zapret-hostlist] $(wc -l <"$OUT") hosts → $OUT"
