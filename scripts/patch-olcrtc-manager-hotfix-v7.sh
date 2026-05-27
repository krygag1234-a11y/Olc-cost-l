#!/usr/bin/env bash
# Hotfix v7: provide updateGuardMiddleware stub when missing.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
if "func updateGuardMiddleware(" not in t:
    anchor = "func updatesRunHandler(w http.ResponseWriter, r *http.Request) {"
    stub = """
func updateGuardMiddleware(next http.Handler) http.Handler {
\treturn http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
\t\tnext.ServeHTTP(w, r)
\t})
}

"""
    if anchor in t:
        t = t.replace(anchor, stub + anchor, 1)
    else:
        t = stub + t

if "olc-manager-hotfix-v7" not in t:
    t = "/* olc-manager-hotfix-v7 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v7] ok")
PY
