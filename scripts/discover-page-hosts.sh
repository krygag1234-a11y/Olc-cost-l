#!/usr/bin/env bash
# Extract hostnames from a page/HTML (for finding player CDN) → append to ru-domains-extra.txt
# Usage: discover-page-hosts.sh 'https://doktor-ktto-lordfilm.ru/14-sezon-1-seriya/'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

URL="${1:-}"
[[ -n "$URL" ]] || { echo "usage: $0 <url>  OR  DISCOVER_HTML=/path/page.html $0 file://local" >&2; exit 1; }

OUT="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
safety_check_output_path OUT "$OUT"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [[ -n "${DISCOVER_HTML:-}" && -f "$DISCOVER_HTML" ]]; then
  cp "$DISCOVER_HTML" "$TMP"
  echo "[discover] using saved HTML: $DISCOVER_HTML" >&2
elif [[ "$URL" == file://* ]]; then
  echo "set DISCOVER_HTML=/path/to/saved.html" >&2
  exit 1
else
  curl -fsSL -A 'Mozilla/5.0' --max-time 25 "$URL" >"$TMP" || {
    echo "[discover] curl failed (403/WAF?). Save page in browser → scp → discover-page-hosts-from-html.sh" >&2
    exit 1
  }
fi

# kinobalancer: atob("aHR0cHM6Ly9hcGku...") API URLs in page source
python3 - "$TMP" <<'PY' 2>/dev/null || true
import re, base64, sys
from urllib.parse import urlparse
html = open(sys.argv[1], errors='replace').read()
for b64 in re.findall(r'atob\("([A-Za-z0-9+/=]+)"\)', html):
    try:
        u = base64.b64decode(b64).decode('utf-8', 'ignore')
        if u.startswith('http'):
            print(urlparse(u).hostname or '')
    except Exception:
        pass
for u in re.findall(r'https?://[a-z0-9][a-z0-9.-]+\.[a-z]{2,}', html, re.I):
    print(urlparse(u).hostname or '')
PY

{
  grep -oiE '[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+' "$TMP" || true
  grep -oiE 'https?://[^/\"'\''<> ]+' "$TMP" | sed 's|https\?://||;s|/.*||' || true
} | tr '[:upper:]' '[:lower:]' | sort -u | while read -r h; do
  [[ -z "$h" ]] && continue
  [[ "$h" == *.* ]] || continue
  echo "suffix:.${h}"
  echo "exact:${h}"
done | awk '!seen[$0]++' >>"$OUT"

echo "appended hosts from $URL → $OUT (review file)"
