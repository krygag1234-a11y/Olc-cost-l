#!/usr/bin/env bash
# Idempotent: cap concurrent Tor dials so direct (VK) traffic is not starved.
set -euo pipefail
SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1
grep -q 'torDialSem' "$SERVER_GO" && {
  echo "[patch-tor-limits] already applied"
  exit 0
}

python3 - "$SERVER_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

const_block = """
const defaultTorDialSlots = 8

"""
if "defaultTorDialSlots" not in t:
    t = t.replace("const connectCommand = \"connect\"\n", "const connectCommand = \"connect\"\n" + const_block, 1)

if "torDialSem" not in t and "torDialSem" not in t.split("type Server struct")[1].split("}")[0]:
    # Try compact format
    if "\tforceTorDomains   *routing.DomainMatcher\n\tliveness" in t:
        t = t.replace(
            "\tforceTorDomains   *routing.DomainMatcher\n\tliveness",
            "\tforceTorDomains   *routing.DomainMatcher\n\ttorDialSem        chan struct{}\n\tliveness",
            1,
        )
    # Try aligned format (BigDaddy 52aea2d)
    elif "\tforceTorDomains              *routing.DomainMatcher\n\tliveness" in t:
        t = t.replace(
            "\tforceTorDomains              *routing.DomainMatcher\n\tliveness",
            "\tforceTorDomains              *routing.DomainMatcher\n\ttorDialSem                   chan struct{}\n\tliveness",
            1,
        )

if "torDialSem: make(chan struct{}, defaultTorDialSlots)" not in t:
    t = t.replace(
        "\t\tdone:           make(chan struct{}),\n\t}",
        "\t\tdone:           make(chan struct{}),\n\t\ttorDialSem:     make(chan struct{}, defaultTorDialSlots),\n\t}",
        1,
    )

old_dial = re.search(r"func \(s \*Server\) dial\(req ConnectRequest\) \(net\.Conn, error\) \{[\s\S]*?\n\}", t)
if not old_dial:
    print("[patch-tor-limits] dial() missing")
    raise SystemExit(1)

new_dial = """func (s *Server) dial(req ConnectRequest) (net.Conn, error) {
\taddr := net.JoinHostPort(req.Addr, strconv.Itoa(req.Port))
\tuseDirect := s.socksProxyAddr == \"\" || s.shouldDialDirect(req.Addr)
\tif useDirect {
\t\tdialer := &net.Dialer{
\t\t\tTimeout:   10 * time.Second,
\t\t\tKeepAlive: 30 * time.Second,
\t\t\tResolver:  s.resolver,
\t\t}
\t\tconn, err := dialer.Dial(\"tcp4\", addr)
\t\tif err != nil {
\t\t\treturn nil, fmt.Errorf(\"dial failed: %w\", err)
\t\t}
\t\treturn conn, nil
\t}

\tif s.torDialSem != nil {
\t\tselect {
\t\tcase s.torDialSem <- struct{}{}:
\t\tcase <-time.After(45 * time.Second):
\t\t\treturn nil, fmt.Errorf(\"tor dial queue timeout for %s\", addr)
\t\t}
\t\tdefer func() { <-s.torDialSem }()
\t}

\tproxyAddr := net.JoinHostPort(s.socksProxyAddr, strconv.Itoa(s.socksProxyPort))
\tdialer := &net.Dialer{
\t\tTimeout:   10 * time.Second,
\t\tKeepAlive: 30 * time.Second,
\t}
\tconn, err := dialer.Dial(\"tcp4\", proxyAddr)
\tif err != nil {
\t\treturn nil, fmt.Errorf(\"failed to dial proxy: %w\", err)
\t}

\tif err := s.socks5Connect(conn, req.Addr, req.Port); err != nil {
\t\t_ = conn.Close()
\t\treturn nil, err
\t}
\treturn conn, nil
}"""
t = t[: old_dial.start()] + new_dial + t[old_dial.end() :]

old_log = '\tlogger.Infof("sid=%d connected %s in %v", stream.ID(), addr, dialElapsed)'
new_log = '''\troute := "direct"
\tif s.socksProxyAddr != "" && !s.shouldDialDirect(req.Addr) {
\t\troute = "tor"
\t}
\tlogger.Infof("sid=%d connect %s route=%s in %v", stream.ID(), addr, route, dialElapsed)'''
if old_log in t:
    t = t.replace(old_log, new_log, 1)

p.write_text(t)
print("[patch-tor-limits] ok")
PY
