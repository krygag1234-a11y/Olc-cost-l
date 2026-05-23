#!/usr/bin/env bash
set -euo pipefail
MAIN="${1:-/tmp/olcrtc-manager-panel/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# --- struct olcrtcSocksConfig ---
if "DirectDomainsFile" not in t:
    t = re.sub(
        r"(type olcrtcSocksConfig struct \{[\s\S]*?DirectCIDRsFile string `yaml:\"direct_cidrs_file,omitempty\"`)\n(\})",
        r"\1\n\tDirectDomainsFile       string `yaml:\"direct_domains_file,omitempty\"`\n\tBlockedTorDomainsFile string `yaml:\"blocked_tor_domains_file,omitempty\"`\n\tForceTorDomainsFile   string `yaml:\"force_tor_domains_file,omitempty\"`\n\2",
        t,
        count=1,
    )

def insert_before_direct_cidrs_env(name, body):
    global t
    if f"func {name}(" in t:
        return
    t = t.replace(
        "func directCIDRsFileFromEnv() string {",
        body + "func directCIDRsFileFromEnv() string {",
        1,
    )

insert_before_direct_cidrs_env(
    "directDomainsFileFromEnv",
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

''',
)

insert_before_direct_cidrs_env(
    "blockedTorDomainsFileFromEnv",
    '''func blockedTorDomainsFileFromEnv() string {
\tif p := strings.TrimSpace(os.Getenv("OLCRTC_BLOCKED_TOR_DOMAINS")); p != "" {
\t\treturn p
\t}
\tconst defaultPath = "/var/lib/olcrtc/ru-blocked-tor-domains.txt"
\tif _, err := os.Stat(defaultPath); err == nil {
\t\treturn defaultPath
\t}
\treturn ""
}

''',
)

insert_before_direct_cidrs_env(
    "forceTorDomainsFileFromEnv",
    '''func forceTorDomainsFileFromEnv() string {
\tif p := strings.TrimSpace(os.Getenv("OLCRTC_FORCE_TOR_DOMAINS")); p != "" {
\t\treturn p
\t}
\tconst defaultPath = "/var/lib/olcrtc/force-tor-domains.txt"
\tif _, err := os.Stat(defaultPath); err == nil {
\t\treturn defaultPath
\t}
\treturn ""
}

''',
)

# --- serverConfig SOCKS block ---
socks_new = """\tif proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
\t\tcfg.SOCKS = olcrtcSocksConfig{
\t\t\tProxyAddr:             proxyAddr,
\t\t\tProxyPort:             proxyPort,
\t\t\tDirectCIDRsFile:       directCIDRsFileFromEnv(),
\t\t\tDirectDomainsFile:     directDomainsFileFromEnv(),
\t\t\tBlockedTorDomainsFile: blockedTorDomainsFileFromEnv(),
\t\t\tForceTorDomainsFile:   forceTorDomainsFileFromEnv(),
\t\t}
\t}"""

if "ForceTorDomainsFile:" not in t:
    t = re.sub(
        r"\tif proxyAddr, proxyPort := exitProxyFromEnv\(\); proxyAddr != \"\" \{[\s\S]*?\n\t\}",
        socks_new,
        t,
        count=1,
    )

p.write_text(t)
print("[patch-manager-domains] ok")
PY
