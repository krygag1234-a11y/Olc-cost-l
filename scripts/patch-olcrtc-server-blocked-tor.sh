#!/usr/bin/env bash
# Idempotent: blocked_tor_domains_file + shouldDialDirect Tor override for RF-blocked .ru
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
        if old not in t and new.split("\n")[0] not in t:
            continue
        t = t.replace(old, new, 1)
    p.write_text(t)

srv, cfg, sess = sys.argv[1:4]

srv_text = Path(srv).read_text()
if "blockedTorDomains *routing.DomainMatcher" not in srv_text:
    patch(srv, [
        ("\tdirectDomains    *routing.DomainMatcher\n\tliveness",
         "\tdirectDomains     *routing.DomainMatcher\n\tblockedTorDomains *routing.DomainMatcher\n\tliveness"),
        ("\tdirectDomains     *routing.DomainMatcher\n\tliveness",
         "\tdirectDomains     *routing.DomainMatcher\n\tblockedTorDomains *routing.DomainMatcher\n\tliveness"),
    ])
if "BlockedTorDomainsFile" not in Path(srv).read_text():
    patch(srv, [
        ("\tDirectDomainsFile string\n\tTransportOptions",
         "\tDirectDomainsFile       string\n\tBlockedTorDomainsFile string\n\tTransportOptions"),
        ("\tDirectDomainsFile       string\n\tTransportOptions",
         "\tDirectDomainsFile       string\n\tBlockedTorDomainsFile string\n\tTransportOptions"),
    ])

t = Path(srv).read_text()
load = """\tif cfg.BlockedTorDomainsFile != "" {
\t\tbt, err := routing.LoadDomainsFile(cfg.BlockedTorDomainsFile)
\t\tif err != nil {
\t\t\treturn fmt.Errorf("load blocked-tor domains: %w", err)
\t\t}
\t\ts.blockedTorDomains = bt
\t\tlogger.Infof("blocked-tor override: %d domains from %s", bt.Len(), cfg.BlockedTorDomainsFile)
\t}

"""
if "load blocked-tor domains" not in t:
    t = t.replace(
        '\t\tlogger.Infof("direct routing: %d domain rules from %s (+ builtin *.ru)", dm.Len(), cfg.DirectDomainsFile)\n\t}\n\n\t// Register shutdown',
        '\t\tlogger.Infof("direct routing: %d domain rules from %s (+ builtin *.ru)", dm.Len(), cfg.DirectDomainsFile)\n\t}\n\n' + load + '\t// Register shutdown',
    )

new_should = """func (s *Server) shouldDialDirect(host string) bool {
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

if Path(cfg).exists() and "BlockedTorDomainsFile" not in Path(cfg).read_text():
    patch(cfg, [
        ("DirectDomainsFile string `yaml:\"direct_domains_file,omitempty\"`",
         "DirectDomainsFile string `yaml:\"direct_domains_file,omitempty\"`\n\tBlockedTorDomainsFile string `yaml:\"blocked_tor_domains_file,omitempty\"`"),
        ("dst.DirectDomainsFile = pickString(dst.DirectDomainsFile, f.SOCKS.DirectDomainsFile)",
         "dst.DirectDomainsFile = pickString(dst.DirectDomainsFile, f.SOCKS.DirectDomainsFile)\n\tdst.BlockedTorDomainsFile = pickString(dst.BlockedTorDomainsFile, f.SOCKS.BlockedTorDomainsFile)"),
        ("dst.DirectDomainsFile = overlayString(dst.DirectDomainsFile, p.SOCKS.DirectDomainsFile)",
         "dst.DirectDomainsFile = overlayString(dst.DirectDomainsFile, p.SOCKS.DirectDomainsFile)\n\tdst.BlockedTorDomainsFile = overlayString(dst.BlockedTorDomainsFile, p.SOCKS.BlockedTorDomainsFile)"),
    ])

st = Path(sess).read_text() if Path(sess).exists() else ""
if st and "BlockedTorDomainsFile" not in st:
    patch(sess, [
        ("DirectDomainsFile     string\n\tVideo",
         "DirectDomainsFile     string\n\tBlockedTorDomainsFile string\n\tVideo"),
        ("DirectDomainsFile: cfg.DirectDomainsFile,\n\t\t\tTransportOptions:",
         "DirectDomainsFile: cfg.DirectDomainsFile,\n\t\t\tBlockedTorDomainsFile: cfg.BlockedTorDomainsFile,\n\t\t\tTransportOptions:"),
    ])

print("[patch-blocked-tor] ok")
PY
