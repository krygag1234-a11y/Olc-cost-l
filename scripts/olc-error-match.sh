#!/usr/bin/env bash
# Test error-catalog patterns against a line or log file.
# Usage:
#   olc-error-match.sh "not-authorized"
#   olc-error-match.sh --file /var/log/olcrtc/foo.log
#   olc-error-match.sh --id jitsi-xmpp-not-authorized "some log line"
set -euo pipefail

REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
CATALOG="${OLC_ERROR_CATALOG:-$REPO_ROOT/data/error-catalog.json}"

usage() {
  echo "Usage: olc-error-match.sh [--file PATH | --id CATALOG_ID] [TEXT]" >&2
  exit 1
}

filter_id=""
file=""
text=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) file="$2"; shift 2 ;;
    --id) filter_id="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) text="$1"; shift ;;
  esac
done

if [[ -n "$file" ]]; then
  [[ -f "$file" ]] || { echo "missing file: $file" >&2; exit 1; }
  text="$(cat "$file")"
fi

[[ -n "$text" ]] || usage
[[ -f "$CATALOG" ]] || { echo "missing catalog: $CATALOG" >&2; exit 1; }

python3 - "$CATALOG" "$filter_id" "$text" <<'PY'
import json, re, sys
catalog_path, filter_id, hay = sys.argv[1:4]
catalog = json.load(open(catalog_path))
found = 0
for e in catalog.get("entries", []):
    eid = e.get("id", "")
    if filter_id and eid != filter_id:
        continue
    pat = e.get("pattern", "")
    if not pat:
        continue
    try:
        rx = re.compile(pat, re.I)
    except re.error as err:
        print(f"BAD_PATTERN {eid}: {err}", file=sys.stderr)
        continue
    for line in hay.splitlines():
        if rx.search(line):
            found += 1
            print(f"MATCH {eid} [{e.get('severity','?')}] {e.get('title','')}")
            print(f"  line: {line[:200]}")
            for fix in e.get("fixes", [])[:3]:
                print(f"  fix: {fix}")
if found == 0:
    print("NO_MATCH")
    sys.exit(1)
PY
