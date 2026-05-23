#!/usr/bin/env bash
# Apply VPS patches to cloned olcrtc + olcrtc-manager before build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PATCH_DIR="${PATCH_DIR:-$REPO_ROOT/patches}"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

OLCRTC_REPO="${OLCRTC_REPO:-/tmp/olcrtc-src}"
MGR_REPO="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}"
safety_validate_git_build_dir "$OLCRTC_REPO" OLCRTC_REPO
safety_validate_git_build_dir "$MGR_REPO" OLCRTC_MGR_REPO
OLCRTC_BRANCH="${OLCRTC_BRANCH:-master}"

log() { echo "[apply-patches] $*"; }

clone_repos() {
  if [[ -d "$OLCRTC_REPO/.git" ]]; then
    :
  elif [[ -e "$OLCRTC_REPO" ]]; then
    rm -rf "$OLCRTC_REPO"
    git clone -b "$OLCRTC_BRANCH" --depth 1 \
      https://github.com/openlibrecommunity/olcrtc.git "$OLCRTC_REPO"
  else
    git clone -b "$OLCRTC_BRANCH" --depth 1 \
      https://github.com/openlibrecommunity/olcrtc.git "$OLCRTC_REPO"
  fi
  if [[ -d "$MGR_REPO/.git" ]]; then
    :
  elif [[ -e "$MGR_REPO" ]]; then
    rm -rf "$MGR_REPO"
    git clone --depth 1 https://github.com/BigDaddy3334/olcrtc-manager-panel.git "$MGR_REPO"
  else
    git clone --depth 1 https://github.com/BigDaddy3334/olcrtc-manager-panel.git "$MGR_REPO"
  fi
}

apply_olcrtc() {
  log "olcrtc patches in $OLCRTC_REPO"
  (cd "$OLCRTC_REPO" && git checkout -f "$OLCRTC_BRANCH" 2>/dev/null || true)
  (cd "$OLCRTC_REPO" && patch -p1 --forward -N <"$PATCH_DIR/olcrtc-core.patch") || {
    log "WARN: olcrtc-core.patch may be already applied"
  }
  install -d "$OLCRTC_REPO/internal/routing"
  install -m 0644 "$PATCH_DIR/olcrtc-routing-cidr.go" "$OLCRTC_REPO/internal/routing/cidr.go"
  install -m 0644 "$PATCH_DIR/olcrtc-routing-domains.go" "$OLCRTC_REPO/internal/routing/domains.go"
  (cd "$OLCRTC_REPO" && patch -p1 --forward -N <"$PATCH_DIR/olcrtc-session-direct-cidrs.patch") 2>/dev/null || true
  (cd "$OLCRTC_REPO" && patch -p1 --forward -N <"$PATCH_DIR/olcrtc-session-domains.patch") 2>/dev/null || true
  (cd "$OLCRTC_REPO" && patch -p1 --forward -N <"$PATCH_DIR/olcrtc-domains-split.patch") 2>/dev/null || true
  bash "$SCRIPT_DIR/patch-olcrtc-server-domains.sh" "$OLCRTC_REPO/internal/server/server.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-blocked-tor.sh" \
    "$OLCRTC_REPO/internal/server/server.go" \
    "$OLCRTC_REPO/internal/config/config.go" \
    "$OLCRTC_REPO/internal/app/session/session.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-force-tor.sh" \
    "$OLCRTC_REPO/internal/server/server.go" \
    "$OLCRTC_REPO/internal/config/config.go" \
    "$OLCRTC_REPO/internal/app/session/session.go"
  bash "$SCRIPT_DIR/patch-olcrtc-server-route-log.sh" "$OLCRTC_REPO/internal/server/server.go"
  # Ensure datachannel payload (fallback if patch hunk failed)
  sed -i 's/defaultMaxPayloadSize = .*/defaultMaxPayloadSize = 16*1024 - 12/' \
    "$OLCRTC_REPO/internal/transport/datachannel/transport.go" 2>/dev/null || true
}

apply_manager() {
  log "manager patches in $MGR_REPO"
  if ! grep -q 'exitProxyReachable' "$MGR_REPO/cmd/olcrtc-manager/main.go" 2>/dev/null; then
    (cd "$MGR_REPO" && patch -p1 --forward -N <"$PATCH_DIR/olcrtc-manager-main.go.patch") 2>/dev/null || \
      bash "$SCRIPT_DIR/patch-olcrtc-manager-core.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  else
    log "manager core patch markers present (skip main.go.patch)"
  fi
  bash "$SCRIPT_DIR/patch-olcrtc-manager-domains.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-link-direct.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-default-link-tor.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-sessions.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-runtime-dir.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go"
  bash "$SCRIPT_DIR/patch-olcrtc-manager-core.sh" "$MGR_REPO/cmd/olcrtc-manager/main.go" 2>/dev/null || true
  bash "$SCRIPT_DIR/patch-olcrtc-manager-panel-link.sh" "$MGR_REPO/src/main.tsx"
  if [[ -f "$MGR_REPO/package.json" ]] && command -v npm >/dev/null 2>&1; then
    if [[ ! -f "$MGR_REPO/admin/dist/index.html" ]] || grep -q 'link: "tor"' "$MGR_REPO/src/main.tsx" 2>/dev/null; then
      (cd "$MGR_REPO" && npm ci 2>/dev/null || npm install) && (cd "$MGR_REPO" && npm run build) || \
        log "WARN: admin UI build failed — using existing admin/dist if any"
    fi
  fi
  # /api/logs without trailing slash — upstream main often has logsHandler already
}

build_binaries() {
  log "build olcrtc"
  (cd "$OLCRTC_REPO" && go build -o /usr/local/bin/olcrtc ./cmd/olcrtc)
  log "build olcrtc-manager"
  (cd "$MGR_REPO" && go build -o /usr/local/bin/olcrtc-manager ./cmd/olcrtc-manager)
}

clone_repos
apply_olcrtc
apply_manager
if [[ "${BUILD:-1}" == "1" ]]; then
  build_binaries
fi
log "done"
