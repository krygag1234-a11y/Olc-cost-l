#!/usr/bin/env bash
# Fetch TOR_BRIDGES_ALL.txt, probe, apply active set.
exec /opt/olcrtc/scripts/tor-bridge-pool.sh --fetch "$@"
