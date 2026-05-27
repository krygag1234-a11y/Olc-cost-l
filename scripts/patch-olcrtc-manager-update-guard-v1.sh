#!/usr/bin/env bash
# Return 503 on mutating API while panel update lock is held.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'updateGuardMiddleware' "$MAIN_GO" && { echo "[patch-update-guard-v1] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()

guard = r'''
func updateGuardMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet || r.Method == http.MethodHead || r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}
		p := r.URL.Path
		if strings.HasPrefix(p, "/api/updates/") || strings.HasPrefix(p, "/api/auth") {
			next.ServeHTTP(w, r)
			return
		}
		if panelUpdateLocked() {
			w.WriteHeader(http.StatusServiceUnavailable)
			writeJSON(w, map[string]any{"error": "panel update in progress", "retry_after_sec": 30})
			return
		}
		next.ServeHTTP(w, r)
	})
}
'''

if 'func updateGuardMiddleware' not in t:
    anchor = 'func panelUpdateLocked() bool {'
    if anchor in t:
        t = t.replace(anchor, guard + '\n' + anchor, 1)

if 'updateGuardMiddleware(handler)' not in t:
    t = t.replace(
        'Handler:           securityHeaders(handler),',
        'Handler:           securityHeaders(updateGuardMiddleware(handler)),',
        1,
    )

p.write_text(t)
print("[patch-update-guard-v1] ok")
PY
