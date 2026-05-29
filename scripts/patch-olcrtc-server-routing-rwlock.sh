#!/usr/bin/env bash
# Idempotent: protect routing matchers with RWMutex (reload vs dial race).
set -euo pipefail
SERVER_GO="${1:-/tmp/olcrtc-src/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1
grep -q 'routingListsMu' "$SERVER_GO" && {
  echo "[patch-routing-rwlock] already applied"
  exit 0
}

python3 - "$SERVER_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "routingListsMu" not in t:
    t = t.replace(
        "\troutingListsStamp  time.Time\n\tdirectCIDRs      *routing.Matcher\n",
        "\troutingListsStamp  time.Time\n\troutingListsMu     sync.RWMutex\n\tdirectCIDRs      *routing.Matcher\n",
        1,
    )

helper = """
func routingListsLatestMtime(paths ...string) time.Time {
\tvar latest time.Time
\tfor _, path := range paths {
\t\tif path == \"\" {
\t\t\tcontinue
\t\t}
\t\tfi, err := os.Stat(path)
\t\tif err != nil {
\t\t\tcontinue
\t\t}
\t\tif fi.ModTime().After(latest) {
\t\t\tlatest = fi.ModTime()
\t\t}
\t}
\treturn latest
}

"""
if "func routingListsLatestMtime" not in t:
    t = t.replace("func routingListsChanged(stamp time.Time, paths ...string) bool {", helper + "func routingListsChanged(stamp time.Time, paths ...string) bool {", 1)

old_should = re.search(r"func \(s \*Server\) shouldDialDirect\(host string\) bool \{[\s\S]*?\n\}", t)
if not old_should:
    print("[patch-routing-rwlock] shouldDialDirect missing")
    raise SystemExit(1)

new_should = """func (s *Server) shouldDialDirect(host string) bool {
\ts.routingListsMu.RLock()
\tforceTor := s.forceTorDomains
\tblockedTor := s.blockedTorDomains
\tdirectDomains := s.directDomains
\tdirectCIDRs := s.directCIDRs
\ts.routingListsMu.RUnlock()

\tif forceTor != nil && forceTor.MatchHostOnly(host) {
\t\treturn false
\t}
\tif blockedTor != nil && blockedTor.MatchHostOnly(host) {
\t\treturn true
\t}
\tif routing.MatchBuiltinRU(host) {
\t\treturn true
\t}
\tif directDomains != nil && directDomains.MatchHostOnly(host) {
\t\treturn true
\t}
\thost = strings.TrimSpace(host)
\tif ip := net.ParseIP(host); ip != nil && directCIDRs != nil && directCIDRs.Len() > 0 {
\t\treturn directCIDRs.Contains(ip)
\t}
\treturn false
}"""
t = t[: old_should.start()] + new_should + t[old_should.end() :]

old_reload = re.search(r"func \(s \*Server\) reloadRoutingLists\(\) error \{[\s\S]*?\n\}", t)
if not old_reload:
    print("[patch-routing-rwlock] reloadRoutingLists missing")
    raise SystemExit(1)

new_reload = """func (s *Server) reloadRoutingLists() error {
\ts.routingReloadMu.Lock()
\tstamp := s.routingListsStamp
\ts.routingReloadMu.Unlock()
\tpaths := []string{s.directCIDRsPath, s.directDomainsPath, s.blockedTorDomainsPath, s.forceTorDomainsPath}
\tif !routingListsChanged(stamp, paths...) {
\t\treturn nil
\t}

\tvar (
\t\tcidrs      *routing.Matcher
\t\tdomains    *routing.DomainMatcher
\t\tblockedTor *routing.DomainMatcher
\t\tforceTor   *routing.DomainMatcher
\t)
\tif s.directCIDRsPath != \"\" {
\t\tm, err := routing.LoadFile(s.directCIDRsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload direct CIDRs: %w\", err)
\t\t}
\t\tcidrs = m
\t}
\tif s.directDomainsPath != \"\" {
\t\tdm, err := routing.LoadDomainsFile(s.directDomainsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload direct domains: %w\", err)
\t\t}
\t\tdomains = dm
\t}
\tif s.blockedTorDomainsPath != \"\" {
\t\tbt, err := routing.LoadDomainsFile(s.blockedTorDomainsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload blocked-tor domains: %w\", err)
\t\t}
\t\tblockedTor = bt
\t}
\tif s.forceTorDomainsPath != \"\" {
\t\tft, err := routing.LoadDomainsFile(s.forceTorDomainsPath)
\t\tif err != nil {
\t\t\treturn fmt.Errorf(\"reload force-tor domains: %w\", err)
\t\t}
\t\tforceTor = ft
\t}

\ts.routingListsMu.Lock()
\tif cidrs != nil {
\t\ts.directCIDRs = cidrs
\t\tlogger.Infof(\"direct routing reloaded: %d RU/CIDR entries from %s\", cidrs.Len(), s.directCIDRsPath)
\t}
\tif domains != nil {
\t\ts.directDomains = domains
\t\tlogger.Infof(\"direct routing reloaded: %d domain rules from %s (+ builtin *.ru)\", domains.Len(), s.directDomainsPath)
\t}
\tif blockedTor != nil {
\t\ts.blockedTorDomains = blockedTor
\t\tlogger.Infof(\"blocked-tor reloaded: %d domains from %s\", blockedTor.Len(), s.blockedTorDomainsPath)
\t}
\tif forceTor != nil {
\t\ts.forceTorDomains = forceTor
\t\tlogger.Infof(\"force-tor reloaded: %d domains from %s\", forceTor.Len(), s.forceTorDomainsPath)
\t}
\ts.routingReloadMu.Lock()
\tif latest := routingListsLatestMtime(paths...); !latest.IsZero() {
\t\ts.routingListsStamp = latest
\t} else {
\t\ts.routingListsStamp = time.Now()
\t}
\ts.routingReloadMu.Unlock()
\ts.routingListsMu.Unlock()
\treturn nil
}"""
t = t[: old_reload.start()] + new_reload + t[old_reload.end() :]

p.write_text(t)
print("[patch-routing-rwlock] ok")
PY
