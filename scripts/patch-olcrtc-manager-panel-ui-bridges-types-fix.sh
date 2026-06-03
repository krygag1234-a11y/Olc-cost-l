#!/usr/bin/env bash
# Fix bridges types selector default value (obfs4 instead of obfs4,webtunnel).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-bridges-types-fix' "$MAIN_TSX" && { echo "[patch-bridges-types-fix] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Add marker
if 'olc-panel-ui-bridges-types-fix' not in t:
    if 'olc-panel-ui-v10' in t:
        t = t.replace('olc-panel-ui-v10', 'olc-panel-ui-v10 olc-panel-ui-bridges-types-fix', 1)
    elif 'olc-panel-ui-v9' in t:
        t = t.replace('olc-panel-ui-v9', 'olc-panel-ui-v9 olc-panel-ui-bridges-types-fix', 1)
    else:
        t = t.replace('import React, {', '/* olc-panel-ui-bridges-types-fix */\nimport React, {', 1)

# Fix bridge types selector default
old = 'value={String(sys.types ?? "obfs4,webtunnel")}'
new = 'value={String(sys.types ?? "obfs4")}'

if old in t:
    t = t.replace(old, new, 1)
    print(f"[patch-bridges-types-fix] Fixed default bridge types in selector")

# Fix refreshPool call default
old_refresh = 'void refreshPool(String(sys.types ?? "obfs4,webtunnel"))'
new_refresh = 'void refreshPool(String(sys.types ?? "obfs4"))'

if old_refresh in t:
    t = t.replace(old_refresh, new_refresh, 1)
    print(f"[patch-bridges-types-fix] Fixed refreshPool default")

p.write_text(t)
print("[patch-bridges-types-fix] ok")
PY
