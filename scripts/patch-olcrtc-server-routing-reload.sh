#!/usr/bin/env bash
# Idempotent: reload split routing lists on SIGUSR1 without dropping sessions.
set -euo pipefail
SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1
grep -q 'func (s \*Server) reloadRoutingLists() error' "$SERVER_GO" && {
  echo "[patch-routing-reload] already applied"
  exit 0
}

python3 - "$SERVER_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Remove broken earlier attempt (wrong logger type / missing imports).
t = re.sub(
    r"\nfunc \(s \*Server\) reloadRoutingLists\(logger names\.Logger\) error \{.*?\n\}\n",
    "\n",
    t,
    count=1,
    flags=re.S,
)
t = re.sub(
    r"\n\treloadRouting := make\(chan os\.Signal, 1\)\n\tsignal\.Notify\(reloadRouting, syscall\.SIGUSR1\)\n\tgo func\(\) \{.*?\n\t\}\(\)\n\n",
    "\n",
    t,
    count=1,
    flags=re.S,
)

for imp in ('"os"', '"os/signal"', '"syscall"'):
    if imp not in t:
        t = t.replace('"net"\n', '"net"\n\t' + imp + '\n', 1)

if "directDomainsPath   string" not in t and "directCIDRsPath" not in t:
    # Try compact format first
    if "\tdirectCIDRs      *routing.Matcher\n" in t:
        t = t.replace(
            "\tdirectCIDRs      *routing.Matcher\n",
            "\tdirectCIDRsPath   string\n\tdirectDomainsPath   string\n\tblockedTorDomainsPath string\n\tforceTorDomainsPath   string\n\tdirectCIDRs      *routing.Matcher\n",
            1,
        )
    # Try aligned format (BigDaddy 52aea2d after patch-olcrtc-core.sh)
    elif "\tdirectCIDRs                  *routing.Matcher\n" in t:
        t = t.replace(
            "\tdirectCIDRs                  *routing.Matcher\n",
            "\tdirectCIDRsPath              string\n\tdirectDomainsPath            string\n\tblockedTorDomainsPath        string\n\tforceTorDomainsPath          string\n\tdirectCIDRs                  *routing.Matcher\n",
            1,
        )

load_assign = """\ts.directCIDRsPath = cfg.DirectCIDRsFile
\ts.directDomainsPath = cfg.DirectDomainsFile
\ts.blockedTorDomainsPath = cfg.BlockedTorDomainsFile
\ts.forceTorDomainsPath = cfg.ForceTorDomainsFile
"""
if "s.directCIDRsPath = cfg.DirectCIDRsFile" not in t:
    t = t.replace(
        "\tif cfg.DirectCIDRsFile != \"\" {\n",
        load_assign + "\tif cfg.DirectCIDRsFile != \"\" {\n",
        1,
    )

reload_fn = """
func (s *Server) reloadRoutingLists() error {
\tif s.directCIDRsPath != \"\" {
\t\tm, err := routing.LoadFile(s.directCIDRsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload direct CIDRs: %w\", err)
\t\t}
\t\ts.directCIDRs = m
\t\tlogger.Infof(\"direct routing reloaded: %d RU/CIDR entries from %s\", m.Len(), s.directCIDRsPath)
\t}
\tif s.directDomainsPath != \"\" {
\t\tdm, err := routing.LoadDomainsFile(s.directDomainsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload direct domains: %w\", err)
\t\t}
\t\ts.directDomains = dm
\t\tlogger.Infof(\"direct routing reloaded: %d domain rules from %s (+ builtin *.ru)\", dm.Len(), s.directDomainsPath)
\t}
\tif s.blockedTorDomainsPath != \"\" {
\t\tbt, err := routing.LoadDomainsFile(s.blockedTorDomainsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload blocked-tor domains: %w\", err)
\t\t}
\t\ts.blockedTorDomains = bt
\t\tlogger.Infof(\"blocked-tor reloaded: %d domains from %s\", bt.Len(), s.blockedTorDomainsPath)
\t}
\tif s.forceTorDomainsPath != \"\" {
\t\tft, err := routing.LoadDomainsFile(s.forceTorDomainsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload force-tor domains: %w\", err)
\t\t}
\t\ts.forceTorDomains = ft
\t\tlogger.Infof(\"force-tor reloaded: %d domains from %s\", ft.Len(), s.forceTorDomainsPath)
\t}
\treturn nil
}

"""
if "func (s *Server) reloadRoutingLists() error" not in t:
    t = t.replace(
        "func (s *Server) shouldDialDirect(host string) bool {",
        reload_fn + "func (s *Server) shouldDialDirect(host string) bool {",
        1,
    )

sig_block = """
\treloadRouting := make(chan os.Signal, 1)
\tsignal.Notify(reloadRouting, syscall.SIGUSR1)
\tgo func() {
\t\tfor range reloadRouting {
\t\t\tif err := s.reloadRoutingLists(); err != nil {
\t\t\t\tlogger.Warnf(\"routing reload failed: %v\", err)
\t\t\t}
\t\t}
\t}()

"""
if "reloadRouting := make(chan os.Signal" not in t:
    t = t.replace(
        "\t// Register shutdown",
        sig_block + "\t// Register shutdown",
        1,
    )

p.write_text(t)
print("[patch-routing-reload] ok")
PY
