#!/usr/bin/env bash
# Non-RU Tor exit nodes (YouTube geo). Append-only torrc.d — does not remove user torrc.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

[[ "${OLCRTC_ENABLE_TOR:-1}" == "1" ]] || exit 0

MARK="# olcrtc: exit countries"
CONF="${TOR_EXIT_CONF:-/etc/tor/torrc.d/olcrtc-exit.conf}"
# Quoted defaults: unquoted {ru},{by} triggers bash brace expansion and breaks torrc.
EXCLUDE="${OLCRTC_TOR_EXCLUDE_EXIT:-'{ru},{by},{ua},{kz},{cn},{ir},{sy}'}"
EXIT="${OLCRTC_TOR_EXIT_NODES:-'{de},{nl},{fi},{pl},{se},{at},{ch}'}"
STRICT="${OLCRTC_TOR_STRICT_NODES:-1}"

safety_path_allowed "$CONF" || exit 1
mkdir -p "$(dirname "$CONF")"

# Rewrite if missing or malformed (older broken `{de,{nl}}` syntax)
if [[ -f "$CONF" ]] && grep -qF "$MARK" "$CONF" 2>/dev/null; then
  if grep -qE 'ExitNodes \{[a-z]+\,\{' "$CONF" 2>/dev/null; then
    echo "[tor-exit] fixing malformed ExitNodes in $CONF"
  else
    echo "[tor-exit] already configured in $CONF"
    exit 0
  fi
fi

safety_backup_file "$CONF"
cat >"$CONF" <<EOF
$MARK
# Managed by Olc-cost-l — override via panel.env / env:
#   OLCRTC_TOR_EXIT_NODES  OLCRTC_TOR_EXCLUDE_EXIT  OLCRTC_TOR_STRICT_NODES
ExcludeExitNodes $EXCLUDE
ExitNodes $EXIT
StrictNodes $STRICT
EOF
chmod 0644 "$CONF"

# Debian/Ubuntu tor: include torrc.d snippets
TORRC="${TORRC:-/etc/tor/torrc}"
if [[ -f "$TORRC" ]] && ! grep -qE '^\s*%include\s+/etc/tor/torrc\.d/\*' "$TORRC" 2>/dev/null; then
  if ! grep -qF 'olcrtc-torrc.d' "$TORRC" 2>/dev/null; then
    safety_backup_file "$TORRC"
    cat >>"$TORRC" <<'EOF'

# olcrtc-torrc.d
%include /etc/tor/torrc.d/*
EOF
  fi
fi

systemctl restart tor@default 2>/dev/null || true
echo "[tor-exit] ExitNodes=$EXIT ExcludeExitNodes=$EXCLUDE StrictNodes=$STRICT"
