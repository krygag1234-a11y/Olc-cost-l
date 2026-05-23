#!/usr/bin/env bash
# Non-RU Tor exit nodes (YouTube geo). Append-only torrc.d — does not remove user torrc.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

[[ "${OLCRTC_ENABLE_TOR:-1}" == "1" ]] || exit 0

MARK="# olcrtc: exit countries"
CONF="${TOR_EXIT_CONF:-/etc/tor/torrc.d/olcrtc-exit.conf}"
# Defaults without ${var:-{a},{b}} — bash brace-expands that form.
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
STRICT="${OLCRTC_TOR_STRICT_NODES:-1}"

safety_path_allowed "$CONF" || exit 1
mkdir -p "$(dirname "$CONF")"

# Rewrite if missing or malformed (quotes, nested braces)
_needs_fix=0
if [[ ! -f "$CONF" ]]; then
  _needs_fix=1
elif grep -qE "ExitNodes ['\"]|ExitNodes \{[a-z]+\,\{" "$CONF" 2>/dev/null; then
  _needs_fix=1
fi
if [[ "$_needs_fix" -eq 0 ]] && grep -qF "$MARK" "$CONF" 2>/dev/null; then
  echo "[tor-exit] already configured in $CONF"
  exit 0
fi

safety_backup_file "$CONF"
cat >"$CONF" <<EOF
$MARK
# Managed by Olc-cost-l — override: OLCRTC_TOR_EXIT_NODES OLCRTC_TOR_EXCLUDE_EXIT
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
