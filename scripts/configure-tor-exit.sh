#!/usr/bin/env bash
# Non-RU Tor exit nodes for YouTube geo. Appends to /etc/tor/torrc (AppArmor blocks torrc.d on Ubuntu).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

[[ "${OLCRTC_ENABLE_TOR:-1}" == "1" ]] || exit 0

MARK="# olcrtc: exit countries"
TORRC="${TORRC:-/etc/tor/torrc}"

if [[ -n "${OLCRTC_TOR_EXCLUDE_EXIT:-}" ]]; then
  EXCLUDE="$OLCRTC_TOR_EXCLUDE_EXIT"
else
  EXCLUDE='{ru},{by},{ua},{kz},{cn},{ir},{sy}'
fi
if [[ -n "${OLCRTC_TOR_EXIT_NODES:-}" ]]; then
  EXIT="$OLCRTC_TOR_EXIT_NODES"
else
  EXIT='{de},{nl},{fi},{pl},{se},{at},{ch}'
fi
STRICT="${OLCRTC_TOR_STRICT_NODES:-0}"

safety_path_allowed "$TORRC" || exit 1

# Drop broken includes from older deploys
sed -i '\|%include /etc/tor/torrc.d/\*|d' "$TORRC" 2>/dev/null || true
sed -i '\|%include /etc/tor/torrc.d/olcrtc-exit.conf|d' "$TORRC" 2>/dev/null || true

if grep -qF "$MARK" "$TORRC" 2>/dev/null; then
  # Update block in place
  safety_backup_file "$TORRC"
  awk -v mark="$MARK" -v ex="$EXCLUDE" -v en="$EXIT" -v st="$STRICT" '
    $0 == mark { print; print "ExcludeExitNodes " ex; print "ExitNodes " en; print "StrictNodes " st; skip=1; next }
    skip && /^StrictNodes/ { next }
    skip && /^ExitNodes/ { next }
    skip && /^ExcludeExitNodes/ { next }
    skip && /^#/ { skip=0 }
    skip && /^$/ { skip=0 }
    { print }
  ' "$TORRC" >"${TORRC}.tmp" && mv "${TORRC}.tmp" "$TORRC"
  echo "[tor-exit] updated in $TORRC"
else
  safety_backup_file "$TORRC"
  cat >>"$TORRC" <<EOF

$MARK
ExcludeExitNodes $EXCLUDE
ExitNodes $EXIT
StrictNodes $STRICT
EOF
  echo "[tor-exit] appended to $TORRC"
fi

systemctl restart tor@default 2>/dev/null || true
echo "[tor-exit] ExitNodes=$EXIT ExcludeExitNodes=$EXCLUDE StrictNodes=$STRICT"
