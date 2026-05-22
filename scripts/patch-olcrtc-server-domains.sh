#!/usr/bin/env bash
# Idempotent: direct_domains + MatchBuiltinRU in olcrtc internal/server/server.go
set -euo pipefail

SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || { echo "missing $SERVER_GO" >&2; exit 1; }

python3 - "$SERVER_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "directDomains    *routing.DomainMatcher" not in t:
    t = t.replace(
        "\tdirectCIDRs      *routing.Matcher\n\tliveness",
        "\tdirectCIDRs      *routing.Matcher\n\tdirectDomains    *routing.DomainMatcher\n\tliveness",
    )

if "DirectDomainsFile string" not in t:
    t = t.replace(
        "\tDirectCIDRsFile   string\n\tTransportOptions",
        "\tDirectCIDRsFile   string\n\tDirectDomainsFile string\n\tTransportOptions",
    )

block = """\tif cfg.DirectDomainsFile != "" {
\t\tdm, err := routing.LoadDomainsFile(cfg.DirectDomainsFile)
\t\tif err != nil {
\t\t\treturn fmt.Errorf("load direct domains: %w", err)
\t\t}
\t\ts.directDomains = dm
\t\tlogger.Infof("direct routing: %d domain rules from %s (+ builtin *.ru)", dm.Len(), cfg.DirectDomainsFile)
\t}

"""
if "LoadDomainsFile" not in t:
    t = t.replace(
        '\t\tlogger.Infof("direct routing: %d RU/CIDR entries from %s", m.Len(), cfg.DirectCIDRsFile)\n\t}\n\n\t// Register shutdown',
        '\t\tlogger.Infof("direct routing: %d RU/CIDR entries from %s", m.Len(), cfg.DirectCIDRsFile)\n\t}\n\n' + block + '\t// Register shutdown',
    )

old = """func (s *Server) shouldDialDirect(host string) bool {
\tif s.directCIDRs == nil || s.directCIDRs.Len() == 0 {
\t\treturn false
\t}"""
new = """func (s *Server) shouldDialDirect(host string) bool {
\tif routing.MatchBuiltinRU(host) {
\t\treturn true
\t}
\tif s.directDomains != nil && s.directDomains.Match(host) {
\t\treturn true
\t}
\tif s.directCIDRs == nil || s.directCIDRs.Len() == 0 {
\t\treturn false
\t}"""
if old in t:
    t = t.replace(old, new)

p.write_text(t)
print("[patch-server-domains] ok:", p)
PY
