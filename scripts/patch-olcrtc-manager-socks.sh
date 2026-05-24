#!/usr/bin/env bash
# Inject Tor SOCKS + split-routing files into serverConfig (upstream 6878fc8+ omits this block).
set -euo pipefail
MAIN="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Extend olcrtcSocksConfig
old_min = """type olcrtcSocksConfig struct {
\tProxyAddr string `yaml:"proxy_addr,omitempty"`
\tProxyPort int    `yaml:"proxy_port,omitempty"`
}"""

new_full = """type olcrtcSocksConfig struct {
\tProxyAddr             string `yaml:"proxy_addr,omitempty"`
\tProxyPort             int    `yaml:"proxy_port,omitempty"`
\tDirectCIDRsFile       string `yaml:"direct_cidrs_file,omitempty"`
\tDirectDomainsFile     string `yaml:"direct_domains_file,omitempty"`
\tBlockedTorDomainsFile string `yaml:"blocked_tor_domains_file,omitempty"`
\tForceTorDomainsFile   string `yaml:"force_tor_domains_file,omitempty"`
}"""

if "ForceTorDomainsFile" not in t and old_min in t:
    t = t.replace(old_min, new_full, 1)
elif "DirectCIDRsFile" in t and "ForceTorDomainsFile" not in t:
    t = t.replace(
        "\tDirectDomainsFile     string `yaml:\"direct_domains_file,omitempty\"`\n}",
        "\tDirectDomainsFile     string `yaml:\"direct_domains_file,omitempty\"`\n\tBlockedTorDomainsFile string `yaml:\"blocked_tor_domains_file,omitempty\"`\n\tForceTorDomainsFile   string `yaml:\"force_tor_domains_file,omitempty\"`\n}",
        1,
    )

env_helpers = """func directCIDRsFileFromEnv() string {
\tif p := strings.TrimSpace(os.Getenv("OLCRTC_DIRECT_CIDRS")); p != "" {
\t\treturn p
\t}
\tconst defaultPath = "/var/lib/olcrtc/ru-cidrs.txt"
\tif _, err := os.Stat(defaultPath); err == nil {
\t\treturn defaultPath
\t}
\treturn ""
}

func directDomainsFileFromEnv() string {
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

"""

if "func directCIDRsFileFromEnv()" not in t:
    t = t.replace("func exitProxyFromEnv()", env_helpers + "func exitProxyFromEnv()", 1)

socks_block = """
\t// link=direct → без Tor/SOCKS; иначе Tor exit + split (RU direct, остальное через SOCKS).
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
\t}
"""

if "useTor := !strings.EqualFold(strings.TrimSpace(loc.Link)" not in t:
    needle = "\tif err := applyTransportPayload(&cfg, loc.Transport); err != nil {\n\t\treturn olcrtcRuntimeConfig{}, err\n\t}\n\treturn cfg, nil"
    if needle not in t:
        raise SystemExit("patch-manager-socks: serverConfig return block not found")
    t = t.replace(
        needle,
        "\tif err := applyTransportPayload(&cfg, loc.Transport); err != nil {\n\t\treturn olcrtcRuntimeConfig{}, err\n\t}" + socks_block + "\n\treturn cfg, nil",
        1,
    )

p.write_text(t)
if "useTor := !strings.EqualFold" not in p.read_text():
    raise SystemExit("patch-manager-socks: SOCKS block missing after patch")
print("[patch-manager-socks] ok")
PY
