#!/usr/bin/env bash
set -euo pipefail
MAIN="${1:-/tmp/olcrtc-manager-panel/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old_struct = """type olcrtcSocksConfig struct {
\tProxyAddr       string `yaml:\"proxy_addr,omitempty\"`
\tProxyPort       int    `yaml:\"proxy_port,omitempty\"`
\tDirectCIDRsFile string `yaml:\"direct_cidrs_file,omitempty\"`
}"""

new_struct = """type olcrtcSocksConfig struct {
\tProxyAddr             string `yaml:\"proxy_addr,omitempty\"`
\tProxyPort             int    `yaml:\"proxy_port,omitempty\"`
\tDirectCIDRsFile       string `yaml:\"direct_cidrs_file,omitempty\"`
\tDirectDomainsFile     string `yaml:\"direct_domains_file,omitempty\"`
\tBlockedTorDomainsFile string `yaml:\"blocked_tor_domains_file,omitempty\"`
\tForceTorDomainsFile   string `yaml:\"force_tor_domains_file,omitempty\"`
}"""

if old_struct in t:
    t = t.replace(old_struct, new_struct, 1)

if "func directDomainsFileFromEnv()" not in t:
    t = t.replace(
        "func directCIDRsFileFromEnv() string {",
        '''func directDomainsFileFromEnv() string {
\tif p := strings.TrimSpace(os.Getenv("OLCRTC_DIRECT_DOMAINS")); p != "" {
\t\treturn p
\t}
\tconst defaultPath = "/var/lib/olcrtc/ru-direct-domains.txt"
\tif _, err := os.Stat(defaultPath); err == nil {
\t\treturn defaultPath
\t}
\treturn ""
}

func blockedTorDomainsFileFromEnv() string {
\tif p := strings.TrimSpace(os.Getenv("OLCRTC_BLOCKED_TOR_DOMAINS")); p != "" {
\t\treturn p
\t}
\tconst defaultPath = "/var/lib/olcrtc/ru-blocked-tor-domains.txt"
\tif _, err := os.Stat(defaultPath); err == nil {
\t\treturn defaultPath
\t}
\treturn ""
}

func forceTorDomainsFileFromEnv() string {
\tif p := strings.TrimSpace(os.Getenv("OLCRTC_FORCE_TOR_DOMAINS")); p != "" {
\t\treturn p
\t}
\tconst defaultPath = "/var/lib/olcrtc/force-tor-domains.txt"
\tif _, err := os.Stat(defaultPath); err == nil {
\t\treturn defaultPath
\t}
\treturn ""
}

func directCIDRsFileFromEnv() string {''',
        1,
    )

old_socks = """\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\tProxyAddr:       proxyAddr,
\t\t\tProxyPort:       proxyPort,
\t\t\tDirectCIDRsFile: directCIDRsFileFromEnv(),
\t\t}"""

new_socks = """\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\tProxyAddr:             proxyAddr,
\t\t\tProxyPort:             proxyPort,
\t\t\tDirectCIDRsFile:       directCIDRsFileFromEnv(),
\t\t\tDirectDomainsFile:     directDomainsFileFromEnv(),
\t\t\tBlockedTorDomainsFile: blockedTorDomainsFileFromEnv(),
\t\t\tForceTorDomainsFile:   forceTorDomainsFileFromEnv(),
\t\t}"""

if old_socks in t:
    t = t.replace(old_socks, new_socks, 1)

p.write_text(t)
if "ForceTorDomainsFile" not in p.read_text():
    raise SystemExit("patch-manager-domains: ForceTorDomainsFile missing after patch")
print("[patch-manager-domains] ok")
PY
