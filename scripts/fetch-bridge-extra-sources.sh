#!/usr/bin/env bash
# Refresh bridge pool from primary list + data/bridge-extra-urls.txt (Tor-Bridges-Collector).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-webtunnel-build.sh
source "$SCRIPT_DIR/lib-webtunnel-build.sh"
export FETCH_MAX_AGE_SEC=0
export BRIDGE_TYPES
BRIDGE_TYPES="$(effective_bridge_types "${BRIDGE_TYPES:-obfs4}")"
exec "$SCRIPT_DIR/tor-bridge-pool.sh" --fetch --url-only --jobs 8 --target 12 \
  --types "$BRIDGE_TYPES" "$@"
