#!/usr/bin/env bash
# Idempotent split-routing core for upstream olcrtc (bb2e1ee+). Replaces olcrtc-core.patch when upstream drifts.
set -euo pipefail

REPO="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}}"
[[ -d "$REPO" ]] || { echo "missing repo $REPO" >&2; exit 1; }

python3 - "$REPO" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
cfg_go = root / "internal/config/config.go"
sess_go = root / "internal/app/session/session.go"
srv_go = root / "internal/server/server.go"
dc_go = root / "internal/transport/datachannel/transport.go"

for p in (cfg_go, sess_go, srv_go):
    if not p.exists():
        print(f"missing {p}"); raise SystemExit(0)

# --- config.go: SOCKS + Apply/ApplyProfile ---
t = cfg_go.read_text()
socks_fields = """\tDirectCIDRsFile       string `yaml:"direct_cidrs_file,omitempty"`
\tDirectDomainsFile     string `yaml:"direct_domains_file,omitempty"`
\tBlockedTorDomainsFile string `yaml:"blocked_tor_domains_file,omitempty"`
\tForceTorDomainsFile   string `yaml:"force_tor_domains_file,omitempty"`"""
if "DirectCIDRsFile" not in t:
    t = t.replace(
        "\tProxyPass string `yaml:\"proxy_pass\"`\n}",
        "\tProxyPass string `yaml:\"proxy_pass\"`\n" + socks_fields + "\n}",
        1,
    )
apply_pick = """\tdst.SOCKSProxyPass = pickString(dst.SOCKSProxyPass, f.SOCKS.ProxyPass)
\tdst.DirectCIDRsFile = pickString(dst.DirectCIDRsFile, f.SOCKS.DirectCIDRsFile)
\tdst.DirectDomainsFile = pickString(dst.DirectDomainsFile, f.SOCKS.DirectDomainsFile)
\tdst.BlockedTorDomainsFile = pickString(dst.BlockedTorDomainsFile, f.SOCKS.BlockedTorDomainsFile)
\tdst.ForceTorDomainsFile = pickString(dst.ForceTorDomainsFile, f.SOCKS.ForceTorDomainsFile)
\tdst.Video.Width = pickInt(dst.Video.Width, f.Video.Width)"""
if "dst.DirectCIDRsFile = pickString" not in t:
    t = t.replace(
        "\tdst.SOCKSProxyPass = pickString(dst.SOCKSProxyPass, f.SOCKS.ProxyPass)\n\tdst.Video.Width = pickInt(dst.Video.Width, f.Video.Width)",
        apply_pick,
        1,
    )
apply_overlay = """\tdst.SOCKSProxyPass = overlayString(dst.SOCKSProxyPass, p.SOCKS.ProxyPass)
\tdst.DirectCIDRsFile = overlayString(dst.DirectCIDRsFile, p.SOCKS.DirectCIDRsFile)
\tdst.DirectDomainsFile = overlayString(dst.DirectDomainsFile, p.SOCKS.DirectDomainsFile)
\tdst.BlockedTorDomainsFile = overlayString(dst.BlockedTorDomainsFile, p.SOCKS.BlockedTorDomainsFile)
\tdst.ForceTorDomainsFile = overlayString(dst.ForceTorDomainsFile, p.SOCKS.ForceTorDomainsFile)
\tdst.Video.Width = overlayInt(dst.Video.Width, p.Video.Width)"""
if "dst.DirectCIDRsFile = overlayString" not in t:
    t = t.replace(
        "\tdst.SOCKSProxyPass = overlayString(dst.SOCKSProxyPass, p.SOCKS.ProxyPass)\n\tdst.Video.Width = overlayInt(dst.Video.Width, p.Video.Width)",
        apply_overlay,
        1,
    )
cfg_go.write_text(t)

# --- session.go: Config + runServer mapping ---
t = sess_go.read_text()
sess_fields = """\tDirectCIDRsFile       string
\tDirectDomainsFile     string
\tBlockedTorDomainsFile string
\tForceTorDomainsFile   string"""
if "DirectCIDRsFile" not in t:
    t = t.replace(
        "\tSOCKSProxyPass        string\n\tVideo                 VideoConfig",
        "\tSOCKSProxyPass        string\n" + sess_fields + "\n\tVideo                 VideoConfig",
        1,
    )
run_srv = """\t\t\tSOCKSProxyPass:        cfg.SOCKSProxyPass,
\t\t\tDirectCIDRsFile:       cfg.DirectCIDRsFile,
\t\t\tDirectDomainsFile:     cfg.DirectDomainsFile,
\t\t\tBlockedTorDomainsFile: cfg.BlockedTorDomainsFile,
\t\t\tForceTorDomainsFile:   cfg.ForceTorDomainsFile,
\t\t\tTransportOptions: opts,"""
if "DirectCIDRsFile:       cfg.DirectCIDRsFile" not in t:
    t = t.replace(
        "\t\t\tSOCKSProxyPass:   cfg.SOCKSProxyPass,\n\t\t\tTransportOptions: opts,",
        run_srv,
        1,
    )
sess_go.write_text(t)

# --- server.go: imports, structs, Run loaders, shouldDialDirect, dial ---
t = srv_go.read_text()
if '"strings"' not in t:
    t = t.replace('"strconv"\n\t"sync"', '"strconv"\n\t"strings"\n\t"sync"', 1)
if "internal/routing" not in t:
    t = t.replace(
        '"github.com/openlibrecommunity/olcrtc/internal/names"\n\t"github.com/openlibrecommunity/olcrtc/internal/runtime"',
        '"github.com/openlibrecommunity/olcrtc/internal/names"\n\t"github.com/openlibrecommunity/olcrtc/internal/routing"\n\t"github.com/openlibrecommunity/olcrtc/internal/runtime"',
        1,
    )
# Add routing matchers to Server struct (support both old and new upstream format)
if "directCIDRs      *routing.Matcher" not in t and "directCIDRs" not in t.split("type Server struct")[1].split("}")[0]:
    # Try old format first (compact tabs)
    if "\tsocksProxyPass string\n\tliveness       control.Config" in t:
        t = t.replace(
            "\tsocksProxyPass string\n\tliveness       control.Config",
            "\tsocksProxyPass string\n\tdirectCIDRs      *routing.Matcher\n\tdirectDomains    *routing.DomainMatcher\n\tblockedTorDomains *routing.DomainMatcher\n\tforceTorDomains   *routing.DomainMatcher\n\tliveness       control.Config",
            1,
        )
    # Try new format (aligned with spaces) - BigDaddy 52aea2d
    elif "\tsocksProxyPass               string\n\tliveness                     control.Config" in t:
        t = t.replace(
            "\tsocksProxyPass               string\n\tliveness                     control.Config",
            "\tsocksProxyPass               string\n\tdirectCIDRs                  *routing.Matcher\n\tdirectDomains                *routing.DomainMatcher\n\tblockedTorDomains            *routing.DomainMatcher\n\tforceTorDomains              *routing.DomainMatcher\n\tliveness                     control.Config",
            1,
        )
if "DirectCIDRsFile   string" not in t:
    t = t.replace(
        "\tSOCKSProxyPass   string\n\tTransportOptions transport.Options",
        "\tSOCKSProxyPass   string\n\tDirectCIDRsFile   string\n\tDirectDomainsFile string\n\tBlockedTorDomainsFile string\n\tForceTorDomainsFile   string\n\tTransportOptions transport.Options",
        1,
    )

load_block = """\tif cfg.DirectCIDRsFile != "" {
\t\tm, err := routing.LoadFile(cfg.DirectCIDRsFile)
\t\tif err != nil {
\t\t\treturn fmt.Errorf("load direct CIDRs: %w", err)
\t\t}
\t\ts.directCIDRs = m
\t\tlogger.Infof("direct routing: %d RU/CIDR entries from %s", m.Len(), cfg.DirectCIDRsFile)
\t}
\tif cfg.DirectDomainsFile != "" {
\t\tdm, err := routing.LoadDomainsFile(cfg.DirectDomainsFile)
\t\tif err != nil {
\t\t\treturn fmt.Errorf("load direct domains: %w", err)
\t\t}
\t\ts.directDomains = dm
\t\tlogger.Infof("direct routing: %d domain rules from %s (+ builtin *.ru)", dm.Len(), cfg.DirectDomainsFile)
\t}
\tif cfg.BlockedTorDomainsFile != "" {
\t\tbt, err := routing.LoadDomainsFile(cfg.BlockedTorDomainsFile)
\t\tif err != nil {
\t\t\treturn fmt.Errorf("load blocked-tor domains: %w", err)
\t\t}
\t\ts.blockedTorDomains = bt
\t\tlogger.Infof("blocked-tor override: %d domains from %s", bt.Len(), cfg.BlockedTorDomainsFile)
\t}
\tif cfg.ForceTorDomainsFile != "" {
\t\tft, err := routing.LoadDomainsFile(cfg.ForceTorDomainsFile)
\t\tif err != nil {
\t\t\treturn fmt.Errorf("load force-tor domains: %w", err)
\t\t}
\t\ts.forceTorDomains = ft
\t\tlogger.Infof("force-tor: %d domains from %s", ft.Len(), cfg.ForceTorDomainsFile)
\t}

"""
if "load direct CIDRs" not in t:
    t = t.replace("\ts.setupResolver()\n\n\t// Register shutdown", "\ts.setupResolver()\n" + load_block + "\t// Register shutdown", 1)

should_fn = """func (s *Server) shouldDialDirect(host string) bool {
\tif s.forceTorDomains != nil && s.forceTorDomains.MatchHostOnly(host) {
\t\treturn false
\t}
\tif s.blockedTorDomains != nil && s.blockedTorDomains.MatchHostOnly(host) {
\t\treturn true
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
if "func (s *Server) shouldDialDirect" not in t:
    t = t.replace(
        "func (s *Server) dial(req ConnectRequest) (net.Conn, error) {",
        should_fn + "\nfunc (s *Server) dial(req ConnectRequest) (net.Conn, error) {",
        1,
    )

if "useDirect := s.socksProxyAddr == \"\"" not in t:
    t = t.replace(
        "\taddr := net.JoinHostPort(req.Addr, strconv.Itoa(req.Port))\n\tif s.socksProxyAddr == \"\" {",
        "\taddr := net.JoinHostPort(req.Addr, strconv.Itoa(req.Port))\n\tuseDirect := s.socksProxyAddr == \"\" || s.shouldDialDirect(req.Addr)\n\tif useDirect {",
        1,
    )

srv_go.write_text(t)

# datachannel payload
if dc_go.exists():
    t = dc_go.read_text()
    t = re.sub(
        r"const defaultMaxPayloadSize = .*",
        "const defaultMaxPayloadSize = 16*1024 - 12",
        t,
        count=1,
    )
    dc_go.write_text(t)

print("[patch-olcrtc-core] ok"); raise SystemExit(0)
PY
