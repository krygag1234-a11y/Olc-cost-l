#!/usr/bin/env bash
# Legacy entry: full sync of zapret exclusions (domains + ipset + optional reload).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/zapret-sync-excludes.sh" "$@"
