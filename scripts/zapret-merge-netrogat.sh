#!/usr/bin/env bash
# Merge Olc-cost-l Jitsi/carrier exclusions into zapret netrogat + nozapret ipset.
set -euo pipefail

OPT="${ZAPRET_OPT:-/opt/zapret}"
NETROGAT="${OPT}/lists/netrogat.txt"
EXTRA="${OLC_REPO_ROOT:-/opt/Olc-cost-l}/data/zapret-netrogat-extra.txt"
[[ -f "$EXTRA" ]] || EXTRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data/zapret-netrogat-extra.txt"

log() { echo "[zapret-netrogat] $*"; }

[[ -f "$NETROGAT" ]] || { log "skip: no $NETROGAT"; exit 0; }

tmp="$(mktemp)"
{
  cat "$NETROGAT" 2>/dev/null || true
  [[ -f "$EXTRA" ]] && grep -vE '^[[:space:]]*#' "$EXTRA" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
} | awk 'NF && !seen[$0]++' >"$tmp"
install -m 0644 "$tmp" "$NETROGAT"
rm -f "$tmp"

# Also add resolved IPs to nozapret ipset (iptables bypass when nfqws hostlist misses)
if command -v ipset >/dev/null && ipset list nozapret &>/dev/null; then
  while IFS= read -r dom; do
    [[ -n "$dom" ]] || continue
    getent ahostsv4 "$dom" 2>/dev/null | awk '{print $1}' | sort -u | while read -r ip; do
      ipset add nozapret "$ip" 2>/dev/null || true
    done
  done < <(grep -vE '^[[:space:]]*#' "$EXTRA" | sed 's/^[[:space:]]*//')
fi

log "merged extras into $NETROGAT ($(wc -l <"$NETROGAT") lines)"
