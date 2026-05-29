#!/usr/bin/env bash
# Skip routing reload when list files on disk did not change.
set -euo pipefail
SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1
grep -q 'routingListsStamp' "$SERVER_GO" && {
  echo "[patch-routing-reload-skip] already applied"
  exit 0
}

python3 - "$SERVER_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "routingListsStamp" not in t:
    t = t.replace(
        "\troutingReloadTimer   *time.Timer\n\tdirectCIDRs      *routing.Matcher\n",
        "\troutingReloadTimer   *time.Timer\n\troutingListsStamp  time.Time\n\tdirectCIDRs      *routing.Matcher\n",
        1,
    )

helper = """
func routingListsChanged(stamp time.Time, paths ...string) bool {
\tlatest := stamp
\tfor _, path := range paths {
\t\tif path == \"\" {
\t\t\tcontinue
\t\t}
\t\tfi, err := os.Stat(path)
\t\tif err != nil {
\t\t\treturn true
\t\t}
\t\tif fi.ModTime().After(latest) {
\t\t\tlatest = fi.ModTime()
\t\t}
\t}
\treturn latest.After(stamp)
}

"""
if "func routingListsChanged" not in t:
    t = t.replace(
        "func (s *Server) scheduleRoutingReload() {",
        helper + "func (s *Server) scheduleRoutingReload() {",
        1,
    )

old = re.compile(
    r"func \(s \*Server\) reloadRoutingLists\(\) error \{\n"
    r"\tif s\.directCIDRsPath",
    re.S,
)
if not old.search(t):
    print("[patch-routing-reload-skip] reloadRoutingLists anchor missing")
    raise SystemExit(1)

new_head = """func (s *Server) reloadRoutingLists() error {
\ts.routingReloadMu.Lock()
\tstamp := s.routingListsStamp
\ts.routingReloadMu.Unlock()
\tif !routingListsChanged(stamp, s.directCIDRsPath, s.directDomainsPath, s.blockedTorDomainsPath, s.forceTorDomainsPath) {
\t\treturn nil
\t}
\tif s.directCIDRsPath"""

t = old.sub(new_head, t, count=1)

if "s.routingListsStamp = time.Now()" not in t:
    t = t.replace(
        "\treturn nil\n}\n\nfunc (s *Server) shouldDialDirect(host string) bool {",
        "\ts.routingReloadMu.Lock()\n\ts.routingListsStamp = time.Now()\n\ts.routingReloadMu.Unlock()\n\treturn nil\n}\n\nfunc (s *Server) shouldDialDirect(host string) bool {",
        1,
    )

p.write_text(t)
print("[patch-routing-reload-skip] ok")
PY
