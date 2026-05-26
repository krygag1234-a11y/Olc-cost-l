#!/usr/bin/env bash
# Install or update Olc-cost-l (auto-detect, resumable).
#
# One URL for everything:
#   curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash
#   curl -fsSL ... | sudo bash -s -- --no-tor          # foreign VPS
#   curl -fsSL ... | sudo bash -s -- --with-warp       # foreign VPS + Cloudflare WARP (без Tor)
#   curl -fsSL ... | sudo bash -s -- --full            # force clean deps + rebuild
#   curl -fsSL ... | sudo bash -s -- --update          # force update only
#   curl -fsSL ... | sudo bash -s -- --resume          # продолжить с последнего успешного шага
#   curl -fsSL ... | sudo bash -s -- --state           # показать состояние
#   curl -fsSL ... | sudo bash -s -- --no-zapret       # пропустить zapret (для тестов)
set -euo pipefail

INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"
REPO_URL="${OLC_REPO_URL:-https://github.com/krygag1234-a11y/Olc-cost-l.git}"
BRANCH="${OLC_REPO_BRANCH:-main}"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

# curl | bash: BASH_SOURCE[0] is unset under set -u
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR=""
fi
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
SHOW_STATE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|--update|--fresh) FORCE_MODE="$1"; BOOT_ARGS+=("$1") ;;
    --resume) BOOT_ARGS+=("$1"); export OLCRTC_RESUME=1 ;;
    --state)  SHOW_STATE=1 ;;
    *) BOOT_ARGS+=("$1") ;;
  esac
  shift
done

if [[ "$SHOW_STATE" -eq 1 ]]; then
  if [[ -f /var/lib/olcrtc/install-state.json ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq . /var/lib/olcrtc/install-state.json
    else
      cat /var/lib/olcrtc/install-state.json
    fi
  else
    echo "no install state yet"
  fi
  exit 0
fi

resilient_git() {
  local op="$1"; shift
  local attempt rc
  for attempt in 1 2 3; do
    rc=0
    timeout 90 git \
      -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 \
      -c http.postBuffer=524288000 \
      "$@" || rc=$?
    if [[ $rc -eq 0 ]]; then
      return 0
    fi
    echo "[install] git $op attempt $attempt failed (rc=$rc), retrying…" >&2
    sleep $((attempt * 5))
  done
  echo "[install] git $op failed after 3 attempts" >&2
  return 1
}

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  echo "[install] clone $REPO_URL → $INSTALL_DIR"
  rm -rf "$INSTALL_DIR.partial"
  resilient_git clone clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR.partial" || {
    echo "[install] FATAL: cannot clone repo. Retry: $0 (network?)" >&2
    rm -rf "$INSTALL_DIR.partial"
    exit 1
  }
  mv "$INSTALL_DIR.partial" "$INSTALL_DIR"
else
  echo "[install] git fetch+update $INSTALL_DIR (resilient)"
  if ! resilient_git fetch -C "$INSTALL_DIR" fetch --depth 50 origin "$BRANCH"; then
    echo "[install] WARN: fetch failed — using existing working tree" >&2
  fi
  if git -C "$INSTALL_DIR" diff --quiet 2>/dev/null && git -C "$INSTALL_DIR" diff --cached --quiet 2>/dev/null; then
    git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH" 2>/dev/null \
      || git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH" 2>/dev/null \
      || true
  else
    echo "[install] local changes on VPS — reset to origin/$BRANCH"
    git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH" 2>/dev/null || \
      git -C "$INSTALL_DIR" reset --hard "$BRANCH" 2>/dev/null || true
  fi
fi

export OLC_REPO_ROOT="$INSTALL_DIR"
# shellcheck source=scripts/lib-git-safe.sh
source "$INSTALL_DIR/scripts/lib-git-safe.sh"
olc_git_safe_register "$INSTALL_DIR"
ln -sfn "$INSTALL_DIR" /opt/olcrtc 2>/dev/null || true
chmod +x "$INSTALL_DIR"/scripts/*.sh "$INSTALL_DIR"/install.sh 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-update.sh" /usr/local/bin/olc-update 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-feature.sh" /usr/local/bin/olc-feature 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-sync-panel-host.sh" /usr/local/bin/olc-sync-panel-host 2>/dev/null || true
ln -sfn "$INSTALL_DIR/scripts/olc-profile.sh" /usr/local/bin/olc-profile 2>/dev/null || true

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
