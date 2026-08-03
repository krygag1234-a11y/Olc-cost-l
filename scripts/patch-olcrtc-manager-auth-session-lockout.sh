#!/usr/bin/env bash
# Do not rate-limit a browser merely because it has no valid session cookie yet.
set -euo pipefail

main_go="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$main_go" ]] || { echo "[auth-session-lockout] target not found: $main_go" >&2; exit 1; }

python3 - "$main_go" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "OLC_AUTH_SESSION_LOCKOUT_V1"
if marker in text:
    print(f"[auth-session-lockout] already applied: {path}")
    raise SystemExit(0)

old = '''		gotUser, gotPass, ok := r.BasicAuth()
		userOK := subtle.ConstantTimeCompare([]byte(gotUser), []byte(user)) == 1
		passOK := subtle.ConstantTimeCompare([]byte(gotPass), []byte(pass)) == 1
		if !ok || !userOK || !passOK {
			authLimiter.Fail(remote)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}'''
new = '''		gotUser, gotPass, ok := r.BasicAuth()
		if !ok {
			// A missing/expired browser session is not a password attempt. The UI
			// can issue several cookie-less API requests while switching to the
			// login view; counting those requests locked the browser before submit.
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		userOK := subtle.ConstantTimeCompare([]byte(gotUser), []byte(user)) == 1
		passOK := subtle.ConstantTimeCompare([]byte(gotPass), []byte(pass)) == 1
		if !userOK || !passOK {
			authLimiter.Fail(remote)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}'''
count = text.count(old)
if count != 1:
    raise SystemExit(f"[auth-session-lockout] adminAuth anchor: expected one match, got {count}")
text = text.replace(old, new, 1)
text += f"\n// {marker}\n"
path.write_text(text)
print(f"[auth-session-lockout] applied: {path}")
PY
