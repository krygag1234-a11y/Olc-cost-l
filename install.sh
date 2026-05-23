#!/usr/bin/env bash
# Install or update Olc-cost-l (auto-detect).
#
# One URL for everything:
#   curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
#   curl -fsSL ... | sudo bash -s -- --no-tor          # foreign VPS
#   curl -fsSL ... | sudo bash -s -- --full            # force clean deps + rebuild
#   curl -fsSL ... | sudo bash -s -- --update          # force update only
set -euo pipefail

INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"
REPO_URL="${OLC_REPO_URL:-https://github.com/krygag1234-a11y/Olc-cost-l.git}"
BRANCH="${OLC_REPO_BRANCH:-main}"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/safety-lib.sh
if [[ -f "$SCRIPT_DIR/scripts/safety-lib.sh" ]]; then
  source "$SCRIPT_DIR/scripts/safety-lib.sh"
else
  # curl | bash: safety-lib not on disk yet — minimal guard
  safety_check_install_dir() {
    case "$1" in
      /|/etc|/etc/*|/usr|/usr/*) echo "REFUSE OLC_INSTALL_DIR=$1" >&2; return 1 ;;
    esac
  }
fi
safety_check_install_dir "$INSTALL_DIR"

FORCE_MODE=""
BOOT_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|--update|--fresh) FORCE_MODE="$1"; BOOT_ARGS+=("$1") ;;
    *) BOOT_ARGS+=("$1") ;;
  esac
  shift
done

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  echo "[install] clone $REPO_URL → $INSTALL_DIR"
  git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
else
  echo "[install] git pull $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH" || git -C "$INSTALL_DIR" pull --ff-only || true
fi

export OLC_REPO_ROOT="$INSTALL_DIR"
ln -sfn "$INSTALL_DIR" /opt/olcrtc 2>/dev/null || true
chmod +x "$INSTALL_DIR"/scripts/*.sh "$INSTALL_DIR"/install.sh 2>/dev/null || true

DETECT="$INSTALL_DIR/scripts/olc-detect-install.sh"
STATE="fresh"
if [[ -x "$DETECT" ]]; then
  STATE="$("$DETECT" 2>/dev/null || echo fresh)"
fi

case "$FORCE_MODE" in
  --full)   MODE=full ;;
  --fresh)  MODE=full ;;
  --update) MODE=update ;;
  *)
    if [[ "$STATE" == "installed" || "$STATE" == "partial" ]]; then
      MODE=update
    else
      MODE=full
    fi
    ;;
esac

echo "[install] detect=$STATE → mode=$MODE"

if [[ "$MODE" == "update" ]]; then
  exec "$INSTALL_DIR/scripts/agent-bootstrap.sh" --update "${BOOT_ARGS[@]}"
else
  exec "$INSTALL_DIR/scripts/agent-bootstrap.sh" --full "${BOOT_ARGS[@]}"
fi
