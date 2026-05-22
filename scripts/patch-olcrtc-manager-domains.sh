#!/usr/bin/env bash
set -euo pipefail
MAIN="${1:-/tmp/olcrtc-manager-panel/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()

if "DirectDomainsFile" not in t:
    t = t.replace(
        "\tDirectCIDRsFile string `yaml:\"direct_cidrs_file,omitempty\"`\n}",
        "\tDirectCIDRsFile   string `yaml:\"direct_cidrs_file,omitempty\"`\n\tDirectDomainsFile string `yaml:\"direct_domains_file,omitempty\"`\n}",
    )

if "directDomainsFileFromEnv" not in t:
    t = t.replace(
        "func directCIDRsFileFromEnv() string {",
        """func directDomainsFileFromEnv() string {
\tif p := strings.TrimSpace(os.Getenv("OLCRTC_DIRECT_DOMAINS")); p != "" {
\t\treturn p
\t}
\tconst defaultPath = "/var/lib/olcrtc/ru-direct-domains.txt"
\tif _, err := os.Stat(defaultPath); err == nil {
\t\treturn defaultPath
\t}
\treturn ""
}

func directCIDRsFileFromEnv() string {""",
    )
    t = t.replace(
        "\t\t\tDirectCIDRsFile: directCIDRsFileFromEnv(),\n\t\t}",
        "\t\t\tDirectCIDRsFile:   directCIDRsFileFromEnv(),\n\t\t\tDirectDomainsFile: directDomainsFileFromEnv(),\n\t\t}",
    )

p.write_text(t)
print("[patch-manager-domains] ok")
PY
