#!/usr/bin/env bash
# Per-location link=direct → no SOCKS block in olcrtc yaml (speed test / RU-only).
set -euo pipefail
MAIN="${1:-}"
[[ -z "$MAIN" ]] && MAIN="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go"
[[ -f "$MAIN" ]] || MAIN="/opt/olcrtc-manager-src/cmd/olcrtc-manager/main.go"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old = """\t// Tor exit + split (RU/CDN direct, остальное через SOCKS), если Tor SOCKS доступен.
\t// Без Tor: agent-bootstrap.sh --no-tor (не задаёт OLCRTC_EXIT_PROXY).
\tif proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\tProxyAddr:             proxyAddr,
\t\t\tProxyPort:             proxyPort,
\t\t\tDirectCIDRsFile:       directCIDRsFileFromEnv(),
\t\t\tDirectDomainsFile:     directDomainsFileFromEnv(),
\t\t\tBlockedTorDomainsFile: blockedTorDomainsFileFromEnv(),
\t\t\tForceTorDomainsFile:   forceTorDomainsFileFromEnv(),
\t\t}
\t}"""

new = """\t// link=direct in panel → без Tor/SOCKS (чистый direct для теста скорости).
\tuseTor := !strings.EqualFold(strings.TrimSpace(loc.Link), "direct")
\tif useTor {
\t\tif proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
\t\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\t\tProxyAddr:             proxyAddr,
\t\t\t\tProxyPort:             proxyPort,
\t\t\t\tDirectCIDRsFile:       directCIDRsFileFromEnv(),
\t\t\t\tDirectDomainsFile:     directDomainsFileFromEnv(),
\t\t\t\tBlockedTorDomainsFile: blockedTorDomainsFileFromEnv(),
\t\t\t\tForceTorDomainsFile:   forceTorDomainsFileFromEnv(),
\t\t\t}
\t\t}
\t}"""

# fallback without blocked/force fields
old2 = """\t// Tor exit + split (RU/CDN direct, остальное через SOCKS), если Tor SOCKS доступен.
\t// Без Tor: agent-bootstrap.sh --no-tor (не задаёт OLCRTC_EXIT_PROXY).
\tif proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\tProxyAddr:         proxyAddr,
\t\t\tProxyPort:         proxyPort,
\t\t\tDirectCIDRsFile:   directCIDRsFileFromEnv(),
\t\t\tDirectDomainsFile: directDomainsFileFromEnv(),
\t\t}
\t}"""

new2 = """\tuseTor := !strings.EqualFold(strings.TrimSpace(loc.Link), "direct")
\tif useTor {
\t\tif proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
\t\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\t\tProxyAddr:         proxyAddr,
\t\t\t\tProxyPort:         proxyPort,
\t\t\t\tDirectCIDRsFile:   directCIDRsFileFromEnv(),
\t\t\t\tDirectDomainsFile: directDomainsFileFromEnv(),
\t\t\t}
\t\t}
\t}"""

if "useTor := !strings.EqualFold" in t:
    print("[patch-manager-link-direct] already patched")
elif old in t:
    t = t.replace(old, new, 1)
elif old2 in t:
    t = t.replace(old2, new2, 1)
else:
    raise SystemExit("patch-manager-link-direct: serverConfig block not found")

p.write_text(t)
print("[patch-manager-link-direct] ok")
PY
