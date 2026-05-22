#!/usr/bin/env bash
# Discover hosts from HTML saved in browser (View Source / Save as) — for WAF-blocked VPS curl
# Usage: discover-page-hosts-from-html.sh /tmp/page.html
set -euo pipefail

HTML="${1:-}"
[[ -f "$HTML" ]] || { echo "usage: $0 <saved.html>" >&2; exit 1; }
[[ -s "$HTML" ]] || { echo "error: $HTML is empty (0 bytes). In browser: Ctrl+S → Webpage, Complete (*.html)" >&2; exit 1; }

OUT="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
export DISCOVER_HTML="$HTML"
bash "$(dirname "$0")/discover-page-hosts.sh" "file://local"
