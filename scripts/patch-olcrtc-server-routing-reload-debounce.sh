#!/usr/bin/env bash
# Coalesce SIGUSR1 routing reloads (reading 20k+ rules blocks the tunnel).
set -euo pipefail
SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1
grep -q 'scheduleRoutingReload' "$SERVER_GO" && {
  echo "[patch-routing-reload-debounce] already applied"
  exit 0
}

python3 - "$SERVER_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "routingReloadMu      sync.Mutex" not in t:
    t = t.replace(
        "\tforceTorDomainsPath   string\n\tdirectCIDRs      *routing.Matcher\n",
        "\tforceTorDomainsPath   string\n\troutingReloadMu      sync.Mutex\n\troutingReloadTimer   *time.Timer\n\tdirectCIDRs      *routing.Matcher\n",
        1,
    )

schedule_fn = """
func (s *Server) scheduleRoutingReload() {
\ts.routingReloadMu.Lock()
\tdefer s.routingReloadMu.Unlock()
\tif s.routingReloadTimer != nil {
\t\ts.routingReloadTimer.Stop()
\t}
\ts.routingReloadTimer = time.AfterFunc(8*time.Second, func() {
\t\tif err := s.reloadRoutingLists(); err != nil {
\t\t\tlogger.Warnf(\"routing reload failed: %v\", err)
\t\t}
\t})
}

"""
if "func (s *Server) scheduleRoutingReload" not in t:
    t = t.replace(
        "func (s *Server) reloadRoutingLists() error {",
        schedule_fn + "func (s *Server) reloadRoutingLists() error {",
        1,
    )

old_sig = re.compile(
    r"\treloadRouting := make\(chan os\.Signal, 1\)\n"
    r"\tsignal\.Notify\(reloadRouting, syscall\.SIGUSR1\)\n"
    r"\tgo func\(\) \{\n"
    r"\t\tfor range reloadRouting \{\n"
    r"\t\t\tif err := s\.reloadRoutingLists\(\); err != nil \{\n"
    r"\t\t\t\tlogger\.Warnf\(\"routing reload failed: %v\", err\)\n"
    r"\t\t\t\}\n"
    r"\t\t\}\n"
    r"\t\}\(\)\n\n",
    re.S,
)
new_sig = """\treloadRouting := make(chan os.Signal, 1)
\tsignal.Notify(reloadRouting, syscall.SIGUSR1)
\tgo func() {
\t\tfor range reloadRouting {
\t\t\ts.scheduleRoutingReload()
\t\t}
\t}()

"""
if old_sig.search(t):
    t = old_sig.sub(new_sig, t, count=1)
elif "scheduleRoutingReload()" not in t:
    t = t.replace(
        "\t// Register shutdown",
        new_sig + "\t// Register shutdown",
        1,
    )

p.write_text(t)
print("[patch-routing-reload-debounce] ok")
PY
