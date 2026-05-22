#!/usr/bin/env bash
# Tor SOCKS только с localhost (не «голый» SOCKS в интернет).
set -euo pipefail

TORRC="${TORRC:-/etc/tor/torrc}"
MARK="# olcrtc: local socks only"

grep -qF "$MARK" "$TORRC" 2>/dev/null && exit 0

cat >>"$TORRC" <<EOF

$MARK
SocksPolicy accept 127.0.0.1/32
SocksPolicy accept ::1/128
SocksPolicy reject *
EOF
systemctl restart tor@default 2>/dev/null || true
echo "Tor SocksPolicy: only 127.0.0.1 / ::1"
