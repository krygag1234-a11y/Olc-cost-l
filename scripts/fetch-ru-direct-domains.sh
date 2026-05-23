#!/usr/bin/env bash
# Merge geosite-ru + optional extras → ru-direct-domains.txt (used by olcrtc manager).
# NOTE: *.ru / .su / .рф are ALWAYS direct in olcrtc binary (builtin) — doktor-ktto-lordfilm.ru included.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${RU_DOMAINS:-/var/lib/olcrtc/ru-direct-domains.txt}"
safety_check_output_path OUT "$OUT"
GEOSITE="${GEOSITE_DOMAINS:-/var/lib/olcrtc/ru-geosite-domains.txt}"
EXTRA="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
EMBED="${RU_EMBED_BALANCERS:-$REPO_ROOT/data/ru-embed-balancers.txt}"
PLAYER="${RU_PLAYER_DOMAINS:-/var/lib/olcrtc/ru-player-cdn-domains.txt}"

bash "$SCRIPT_DIR/fetch-geosite-ru-domains.sh"
bash "$SCRIPT_DIR/fetch-player-cdn-domains.sh"
bash "$SCRIPT_DIR/fetch-force-tor-domains.sh"
FORCE="${FORCE_TOR_DOMAINS:-/var/lib/olcrtc/force-tor-domains.txt}"

tmp="$(mktemp)"
{
  echo "# Merged direct domain rules — $(date -Iseconds)"
  echo "# Builtin olcrtc: ALL hosts ending in .ru .su .рф (any mirror, e.g. doktor-ktto-lordfilm.ru)"
  [[ -f "$GEOSITE" ]] && grep -v '^#' "$GEOSITE" | awk 'NF'
  [[ -f "$EMBED" ]] && grep -v '^#' "$EMBED" | awk 'NF'
  [[ -f "$PLAYER" ]] && grep -v '^#' "$PLAYER" | awk 'NF'
  [[ -f "$EXTRA" ]] && grep -v '^#' "$EXTRA" | awk 'NF'
} | awk '!seen[$0]++' >"$tmp"

# Drop rules that duplicate force-tor (e.g. youtube from geosite category)
python3 - "$tmp" "$FORCE" "$OUT" <<'PY'
import sys
from pathlib import Path

def load_rules(path):
    exact, suffix = set(), []
    if not Path(path).is_file():
        return exact, suffix
    for line in Path(path).read_text().splitlines():
        line = line.split("#", 1)[0].strip().lower()
        if not line:
            continue
        if line.startswith("exact:"):
            exact.add(line[6:])
        elif line.startswith("suffix:"):
            suffix.append(line[7:])
        else:
            s = line if line.startswith(".") else ("." + line if "." in line else line)
            if s.startswith("."):
                suffix.append(s)
            else:
                exact.add(line)
    return exact, suffix

def blocked(host, exact, suffix):
    host = host.strip().lower()
    if not host:
        return False
    if host in exact:
        return True
    for e in exact:
        if host == e or host.endswith("." + e):
            return True
    for s in suffix:
        if not s.startswith("."):
            s = "." + s
        if host == s[1:] or host.endswith(s):
            return True
    return False

src, force_path, out = sys.argv[1:4]
fe, fs = load_rules(force_path)
kept = []
for line in Path(src).read_text().splitlines():
    raw = line.strip()
    if not raw or raw.startswith("#"):
        kept.append(line)
        continue
    rule = raw.split("#", 1)[0].strip().lower()
    test_hosts = []
    if rule.startswith("exact:"):
        test_hosts = [rule[6:]]
    elif rule.startswith("suffix:"):
        test_hosts = ["x" + rule[7:]]
    elif rule.startswith("."):
        test_hosts = ["x" + rule]
    else:
        test_hosts = [rule, "x." + rule]
    if any(blocked(h, fe, fs) for h in test_hosts):
        continue
    kept.append(line)
Path(out).write_text("\n".join(kept) + ("\n" if kept else ""))
PY
rm -f "$tmp"

echo "merged $(grep -cvE '^#|^$' "$OUT" || echo 0) domain rules → $OUT (force-tor excluded)"
