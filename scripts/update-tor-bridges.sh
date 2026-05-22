#!/usr/bin/env bash
# Fetch TOR_BRIDGES_ALL.txt, probe, apply active set.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/tor-bridge-pool.sh" --fetch "$@"
