#!/usr/bin/env bash
# UI tweak for Jitsi preflight severity coloring/messages.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-jitsi-preflight-ui-v2' "$MAIN_TSX" && { echo "[patch-panel-jitsi-preflight-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "olc-jitsi-preflight-ui-v2" not in t:
    t = t.replace("/* olc-jitsi-preflight-ui-v1 */", "/* olc-jitsi-preflight-ui-v1 */\n/* olc-jitsi-preflight-ui-v2 */", 1)

old = '          <p className={result.ok ? "text-emerald-400" : "text-amber-300"}>'
new = '          <p className={result.ok ? "text-emerald-400" : (result.code === "jitsi-websocket-404" || result.code === "invalid-room" ? "text-destructive" : "text-amber-300")}>'
if old in t:
    t = t.replace(old, new, 1)

p.write_text(t)
print("[patch-panel-jitsi-preflight-v2] ok"); raise SystemExit(0)
PY

