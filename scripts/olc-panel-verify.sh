#!/usr/bin/env bash
# Verify the canonical vendored manager source and its prebuilt UI bundle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SOURCE="${OLC_VENDORED_MANAGER_SOURCE:-$REPO_ROOT/components/olcrtc-manager}"
BUILD_COPY="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}"

log() { echo "[panel-verify] $*"; }

OLC_ALLOW_VENDORED_BUILD_STATE=1 bash "$SCRIPT_DIR/verify-vendored-manager.sh" "$SOURCE"
if [[ -d "$BUILD_COPY" && "$BUILD_COPY" != "$SOURCE" ]]; then
  bash "$SCRIPT_DIR/verify-vendored-manager.sh" "$BUILD_COPY"
  log "temporary build copy: OK"
fi
log "OK: vendored manager source is authoritative"
