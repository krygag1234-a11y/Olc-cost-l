#!/usr/bin/env bash
# One-command full uninstall of Olc-cost-l stack on this VPS.
#
#   curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/uninstall.sh | sudo bash
#   curl -fsSL .../uninstall.sh | sudo bash -s -- --purge-repo
#   curl -fsSL .../uninstall.sh | sudo bash -s -- --keep-tor
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"
REPO_URL="${OLC_REPO_URL:-https://github.com/krygag1234-a11y/Olc-cost-l.git}"
BRANCH="${OLC_REPO_BRANCH:-main}"

# If repo on disk — use local purge script
if [[ -f "$INSTALL_DIR/scripts/olc-purge.sh" ]]; then
  exec bash "$INSTALL_DIR/scripts/olc-purge.sh" "$@"
fi

# curl | bash: clone minimal to run purge, then --purge-repo removes clone too
TMP_REPO="$(mktemp -d /tmp/olc-purge-XXXXXX)"
trap 'rm -rf "$TMP_REPO"' EXIT
git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$TMP_REPO"
exec bash "$TMP_REPO/scripts/olc-purge.sh" --purge-repo "$@"
