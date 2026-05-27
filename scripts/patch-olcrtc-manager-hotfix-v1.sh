#!/usr/bin/env bash
# Hotfix v1: stable feature guards + routing behavior on manager backend.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v1' "$MAIN_GO" && { echo "[patch-manager-hotfix-v1] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Ensure feature toggle blocks webtunnel when Tor is disabled.
needle = """\t\targ := "off"
\t\tif body.Enabled {
\t\t\targ = "on"
\t\t}
"""
inject = """\t\targ := "off"
\t\tif body.Enabled {
\t\t\targ = "on"
\t\t}
\t\tif name == "webtunnel" && body.Enabled {
\t\t\tflagsNow := readFeatureFlags()
\t\t\tif !flagsNow["tor"] {
\t\t\t\thttp.Error(w, "bridges require tor enabled", http.StatusBadRequest)
\t\t\t\treturn
\t\t\t}
\t\t}
"""
if needle in t and 'bridges require tor enabled' not in t:
    t = t.replace(needle, inject, 1)

# Capabilities: bridges require tor.
caps_old = 'Configurable: componentInstalled("tor"), Label: "Мосты",'
caps_new = 'Configurable: componentInstalled("tor"), Label: "Мосты", Requires: []string{"tor"},'
if caps_old in t and 'Requires: []string{"tor"},' not in t[t.find('"bridges"'):t.find('"bridges"')+260]:
    t = t.replace(caps_old, caps_new, 1)

# serverConfig: apply split/zapret routing files only when corresponding features are enabled.
sc_old = """\tif useTor {
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
\t}
"""
sc_new = """\tif useTor {
\t\tif proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
\t\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\t\tProxyAddr: proxyAddr,
\t\t\t\tProxyPort: proxyPort,
\t\t\t}
\t\t\tflags := readFeatureFlags()
\t\t\tif flags["split"] || flags["zapret"] {
\t\t\t\tcfg.SOCKS.DirectCIDRsFile = directCIDRsFileFromEnv()
\t\t\t\tcfg.SOCKS.DirectDomainsFile = directDomainsFileFromEnv()
\t\t\t\tcfg.SOCKS.BlockedTorDomainsFile = blockedTorDomainsFileFromEnv()
\t\t\t\tcfg.SOCKS.ForceTorDomainsFile = forceTorDomainsFileFromEnv()
\t\t\t}
\t\t}
\t}
"""
if sc_old in t:
    t = t.replace(sc_old, sc_new, 1)

# Ensure preflight route exists.
if '/api/jitsi/preflight' not in t:
    route = '\thandler.Handle("/api/jitsi/preflight", adminAuth(http.HandlerFunc(jitsiPreflightHandler)))\n'
    anchor = '\thandler.Handle("/api/capabilities", adminAuth(http.HandlerFunc(capabilitiesHandler())))\n'
    if anchor in t:
        t = t.replace(anchor, route + anchor, 1)

if 'olc-manager-hotfix-v1' not in t:
    t = t.replace("func run() error {", "/* olc-manager-hotfix-v1 */\nfunc run() error {", 1)

p.write_text(t)
print("[patch-manager-hotfix-v1] ok")
PY
