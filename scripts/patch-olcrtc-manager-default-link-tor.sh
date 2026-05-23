#!/usr/bin/env bash
# Panel buildLocations() used link=direct when API omitted link → no SOCKS on new clients.
set -euo pipefail
MAIN="${1:-${OLCRTC_MANAGER_MAIN:-/tmp/olcrtc-manager-panel/cmd/olcrtc-manager/main.go}}"
[[ -f "$MAIN" ]] || { echo "missing $MAIN"; exit 1; }
if grep -q 'func defaultLocationLink()' "$MAIN"; then
  echo "[patch] default link tor: already applied"
  exit 0
fi
python3 - "$MAIN" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
if "func defaultLocationLink()" in t:
    print("already patched")
    sys.exit(0)
t = t.replace(
    'type locationRequest struct {\n\tName      string',
    'type locationRequest struct {\n\tName      string',
)
t = re.sub(
    r'(type locationRequest struct \{[^}]+DNS       string[^\n]+\n)\}',
    r'\1\tLink      string            `json:"link"`\n}',
    t,
    count=1,
)
t = t.replace(
    '\tLink:      "direct",',
    '\tLink:      defaultString(strings.TrimSpace(req.Link), defaultLocationLink()),',
)
fn = '''
// defaultLocationLink: panel/API default link (OLCRTC_DEFAULT_LINK, else tor).
func defaultLocationLink() string {
\tif v := strings.TrimSpace(os.Getenv("OLCRTC_DEFAULT_LINK")); v != "" {
\t\treturn strings.ToLower(v)
\t}
\treturn "tor"
}

'''
t = t.replace('func buildLocations(clientID string, requests []locationRequest)', fn + 'func buildLocations(clientID string, requests []locationRequest)', 1)
p.write_text(t)
print("[patch] default link tor: ok")
PY
