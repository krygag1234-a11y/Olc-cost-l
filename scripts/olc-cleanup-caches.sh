#!/usr/bin/env bash
# Clean temporary Olc-cost-l build caches without uninstalling services.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-cache-cleanup.sh
source "$SCRIPT_DIR/lib-cache-cleanup.sh"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
olc_cleanup_build_caches "manual"
df -h / /tmp
