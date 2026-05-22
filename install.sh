#!/usr/bin/env bash
# Install Olc-cost-l to /opt/Olc-cost-l and run bootstrap.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
#   curl -fsSL ... | sudo bash -s -- --no-tor
set -euo pipefail

INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"
REPO_URL="${OLC_REPO_URL:-https://github.com/krygag1234-a11y/Olc-cost-l.git}"
BRANCH="${OLC_REPO_BRANCH:-main}"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/safety-lib.sh
source "$SCRIPT_DIR/scripts/safety-lib.sh"
safety_check_install_dir "$INSTALL_DIR"

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
else
  git -C "$INSTALL_DIR" pull --ff-only || true
fi

export OLC_REPO_ROOT="$INSTALL_DIR"
ln -sfn "$INSTALL_DIR" /opt/olcrtc
chmod +x "$INSTALL_DIR"/scripts/*.sh "$INSTALL_DIR"/install.sh 2>/dev/null || true
# По умолчанию RU VPS (Tor+split). Иностранный: bash -s -- --no-tor
exec "$INSTALL_DIR/scripts/agent-bootstrap.sh" "$@"
