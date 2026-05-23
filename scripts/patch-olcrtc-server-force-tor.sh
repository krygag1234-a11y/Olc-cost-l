#!/usr/bin/env bash
# Idempotent: force_tor_domains_file — always Tor (YouTube/googlevideo etc.)
set -euo pipefail
SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
CONFIG_GO="${2:-/tmp/olcrtc-src/internal/config/config.go}"
SESSION_GO="${3:-/tmp/olcrtc-src/internal/app/session/session.go}"
[[ -f "$SERVER_GO" ]] || exit 1

python3 - "$SERVER_GO" "$CONFIG_GO" "$SESSION_GO" <<'PY'
import sys, re
from pathlib import Path

def patch(path, edits):
    p = Path(path)
    t = p.read_text()
    for old, new in edits:
        if old in t:
            t = t.replace(old, new, 1)
    p.write_text(t)

srv, cfg, sess = sys.argv[1:4]
t = Path(srv).read_text()

if "forceTorDomains *routing.DomainMatcher" not in t:
    patch(srv, [
        ("\tblockedTorDomains *routing.DomainMatcher\n\tliveness",
         "\tblockedTorDomains *routing.DomainMatcher\n\tforceTorDomains   *routing.DomainMatcher\n\tliveness"),
    ])

if "ForceTorDomainsFile" not in t:
    patch(srv, [
        ("\tBlockedTorDomainsFile string\n\tTransportOptions",
         "\tBlockedTorDomainsFile string\n\tForceTorDomainsFile   string\n\tTransportOptions"),
    ])

t = Path(srv).read_text()
load = """\tif cfg.ForceTorDomainsFile != "" {
\t\tft, err := routing.LoadDomainsFile(cfg.ForceTorDomainsFile)
\t\tif err != nil {
\t\t\treturn fmt.Errorf("load force-tor domains: %w", err)
\t\t}
\t\ts.forceTorDomains = ft
\t\tlogger.Infof("force-tor: %d domains from %s", ft.Len(), cfg.ForceTorDomainsFile)
\t}

"""
if "load force-tor domains" not in t:
    t = t.replace(
        '\t\tlogger.Infof("blocked-tor override: %d domains from %s", bt.Len(), cfg.BlockedTorDomainsFile)\n\t}\n\n\t// Register shutdown',
        '\t\tlogger.Infof("blocked-tor override: %d domains from %s", bt.Len(), cfg.BlockedTorDomainsFile)\n\t}\n\n' + load + '\t// Register shutdown',
    )
    if "load force-tor domains" not in t:
        t = t.replace(
            '\t\tlogger.Infof("direct routing: %d domain rules from %s (+ builtin *.ru)", dm.Len(), cfg.DirectDomainsFile)\n\t}\n\n\t// Register shutdown',
            '\t\tlogger.Infof("direct routing: %d domain rules from %s (+ builtin *.ru)", dm.Len(), cfg.DirectDomainsFile)\n\t}\n\n' + load + '\t// Register shutdown',
        )

new_should = """func (s *Server) shouldDialDirect(host string) bool {
\tif s.forceTorDomains != nil && s.forceTorDomains.MatchHostOnly(host) {
\t\treturn false
\t}
\tif s.blockedTorDomains != nil && s.blockedTorDomains.MatchHostOnly(host) {
\t\treturn false
\t}
\tif routing.MatchBuiltinRU(host) {
\t\treturn true
\t}
\tif s.directDomains != nil && s.directDomains.MatchHostOnly(host) {
\t\treturn true
\t}
\thost = strings.TrimSpace(host)
\tif ip := net.ParseIP(host); ip != nil && s.directCIDRs != nil && s.directCIDRs.Len() > 0 {
\t\treturn s.directCIDRs.Contains(ip)
\t}
\treturn false
}
"""
m = re.search(r"func \(s \*Server\) shouldDialDirect\(host string\) bool \{[\s\S]*?\n\}", t)
if m:
    t = t[: m.start()] + new_should + t[m.end() :]
Path(srv).write_text(t)

if Path(cfg).exists() and "ForceTorDomainsFile" not in Path(cfg).read_text():
    patch(cfg, [
        ("BlockedTorDomainsFile string `yaml:\"blocked_tor_domains_file,omitempty\"`",
         "BlockedTorDomainsFile string `yaml:\"blocked_tor_domains_file,omitempty\"`\n\tForceTorDomainsFile   string `yaml:\"force_tor_domains_file,omitempty\"`"),
        ("dst.BlockedTorDomainsFile = pickString(dst.BlockedTorDomainsFile, f.SOCKS.BlockedTorDomainsFile)",
         "dst.BlockedTorDomainsFile = pickString(dst.BlockedTorDomainsFile, f.SOCKS.BlockedTorDomainsFile)\n\tdst.ForceTorDomainsFile = pickString(dst.ForceTorDomainsFile, f.SOCKS.ForceTorDomainsFile)"),
        ("dst.BlockedTorDomainsFile = overlayString(dst.BlockedTorDomainsFile, p.SOCKS.BlockedTorDomainsFile)",
         "dst.BlockedTorDomainsFile = overlayString(dst.BlockedTorDomainsFile, p.SOCKS.BlockedTorDomainsFile)\n\tdst.ForceTorDomainsFile = overlayString(dst.ForceTorDomainsFile, p.SOCKS.ForceTorDomainsFile)"),
    ])

st = Path(sess).read_text() if Path(sess).exists() else ""
if st and "ForceTorDomainsFile" not in st:
    patch(sess, [
        ("BlockedTorDomainsFile string\n\tVideo",
         "BlockedTorDomainsFile string\n\tForceTorDomainsFile   string\n\tVideo"),
        ("BlockedTorDomainsFile: cfg.BlockedTorDomainsFile,\n\t\t\tTransportOptions:",
         "BlockedTorDomainsFile: cfg.BlockedTorDomainsFile,\n\t\t\tForceTorDomainsFile:   cfg.ForceTorDomainsFile,\n\t\t\tTransportOptions:"),
    ])

print("[patch-force-tor] ok")
PY
