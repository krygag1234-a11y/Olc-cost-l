#!/usr/bin/env bash
# Idempotent: log connect route=direct|tor
set -euo pipefail
SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1
grep -q 'route=%s' "$SERVER_GO" && exit 0
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches"
OLCRTC_REPO="$(cd "$(dirname "$SERVER_GO")/../.." && pwd)"
if (cd "$OLCRTC_REPO" && patch -p1 --forward -N <"$PATCH_DIR/olcrtc-dial-route-log.patch") 2>/dev/null; then
  echo "[patch-route-log] ok (patch)"
  exit 0
fi
python3 - "$SERVER_GO" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
old = '\tlogger.Infof("sid=%d connected %s in %v", stream.ID(), addr, dialElapsed)'
new = '''\troute := "direct"
\tif s.socksProxyAddr != "" && !s.shouldDialDirect(req.Addr) {
\t\troute = "tor"
\t}
\tlogger.Infof("sid=%d connect %s route=%s in %v", stream.ID(), addr, route, dialElapsed)'''
if old not in t:
    print("connect log line not found"); raise SystemExit(0)
p.write_text(t.replace(old, new, 1))
print("[patch-route-log] ok"); raise SystemExit(0)
PY
