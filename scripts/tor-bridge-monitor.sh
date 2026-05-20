#!/usr/bin/env bash
# Periodic bridge health probe (no Tor restart). Run from cron/timer.
exec "$(dirname "$0")/tor-bridge-pool.sh" --monitor "$@"
