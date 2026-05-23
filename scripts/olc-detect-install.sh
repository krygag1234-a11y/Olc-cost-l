#!/usr/bin/env bash
# Detect existing Olc-cost-l deployment (repo + panel + olcrtc units).
set -euo pipefail

INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"
MARKER=0

[[ -d "$INSTALL_DIR/.git" ]] && MARKER=$((MARKER + 1))
[[ -x /usr/local/bin/olcrtc-manager ]] && MARKER=$((MARKER + 1))
[[ -f /etc/olcrtc-manager/panel.env ]] && MARKER=$((MARKER + 1))
systemctl list-unit-files 'olcrtc-*' &>/dev/null && MARKER=$((MARKER + 1))

# Legacy / partial install
[[ -L /opt/olcrtc || -d /opt/olcrtc/scripts ]] && MARKER=$((MARKER + 1))

if [[ "$MARKER" -ge 3 ]]; then
  echo installed
  exit 0
fi
if [[ "$MARKER" -ge 1 ]]; then
  echo partial
  exit 2
fi
echo fresh
exit 1
