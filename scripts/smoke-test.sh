#!/usr/bin/env bash
# Quick sanity check for Olc-cost-l scripts (CI / post-deploy / test VPS).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FAIL=0
ok() { echo "[smoke] OK: $*"; }
bad() { echo "[smoke] FAIL: $*" >&2; FAIL=1; }

echo "[smoke] repo=$REPO_ROOT"

# Syntax check all shell scripts
while IFS= read -r -d '' sh; do
  bash -n "$sh" || bad "bash -n $sh"
done < <(find "$REPO_ROOT/scripts" -maxdepth 1 -name '*.sh' -print0)
[[ "$FAIL" -eq 0 ]] && ok "bash -n scripts/*.sh"

# Required data files
for f in \
  data/upstream-pins.json \
  data/zapret-netrogat-extra.txt \
  data/zapret-carrier-hosts.txt \
  data/zapret-community-excludes/flowseal-list-exclude.txt; do
  [[ -f "$REPO_ROOT/$f" ]] || bad "missing $f"
done
ok "required data files"

# Help / dry paths (must not require root)
for cmd in \
  "$SCRIPT_DIR/upstream-sync.sh --help" \
  "$SCRIPT_DIR/fetch-zapret-community-excludes.sh"; do
  eval "$cmd" >/dev/null 2>&1 || bad "$cmd"
done
ok "help/fetch scripts"

# zapret-sync domains-only if zapret installed
if [[ -f /opt/zapret/lists/netrogat.txt ]]; then
  if timeout 120 env OLCRTC_ZAPRET_RESOLVE_IPS=0 bash "$SCRIPT_DIR/zapret-sync-excludes.sh" --domains-only >/dev/null 2>&1; then
    ok "zapret-sync-excludes --domains-only"
  else
    bad "zapret-sync-excludes (timeout 120s)"
  fi
else
  echo "[smoke] skip zapret-sync (no /opt/zapret)"
fi

# Tor SOCKS optional
if timeout 1 bash -lc ':</dev/tcp/127.0.0.1/9050' 2>/dev/null; then
  ok "tor SOCKS port open"
else
  echo "[smoke] skip tor (9050 closed)"
fi

[[ "$FAIL" -eq 0 ]] || exit 1
echo "[smoke] all checks passed"
