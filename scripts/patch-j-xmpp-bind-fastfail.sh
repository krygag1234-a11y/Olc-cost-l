#!/usr/bin/env bash
# Fail fast when Prosody rejects XMPP bind (e.g. "Error loading roster") instead of ~60s EOF wait.
set -euo pipefail

OLCRTC_REPO="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}}"
[[ -d "$OLCRTC_REPO" ]] || exit 0

if [[ -x /usr/local/go/bin/go ]]; then
  export PATH="/usr/local/go/bin:$PATH"
fi
export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"

J_DIR="$(cd "$OLCRTC_REPO" && go list -m -json github.com/zarazaex69/j 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Dir",""))' 2>/dev/null || true)"
[[ -n "$J_DIR" && -f "$J_DIR/internal/xmpp/conn.go" ]] || {
  echo "[patch-j-xmpp] skip: zarazaex69/j module not found"
  exit 0
}

CONN_GO="$J_DIR/internal/xmpp/conn.go"
if grep -q 'bind rejected' "$CONN_GO" 2>/dev/null; then
  echo "[patch-j-xmpp] already patched"
  exit 0
fi

python3 - "$CONN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
needle = "\t\tif strings.Contains(msg, substr) {\n\t\t\treturn msg, nil\n\t\t}\n"
insert = needle + """\t\tif strings.Contains(msg, "type='error'") || strings.Contains(msg, `type="error"`) {
\t\t\tif strings.Contains(msg, "bind_1") || strings.Contains(msg, "urn:ietf:params:xml:ns:xmpp-bind") {
\t\t\t\treturn "", fmt.Errorf("bind rejected: %s", msg)
\t\t\t}
\t\t}
"""
if needle not in t:
    raise SystemExit("readUntilReturn block not found")
t = t.replace(needle, insert, 1)
p.write_text(t)
print("[patch-j-xmpp] ok")
PY
