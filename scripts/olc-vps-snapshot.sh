#!/usr/bin/env bash
# Снимок состояния VPS в packaging/vps-snapshot/ (для отладки и «синк olc»).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUT="${OLC_SNAPSHOT_DIR:-$REPO_ROOT/packaging/vps-snapshot}"

log() { echo "[vps-snapshot] $*"; }

install -d "$OUT"
log "→ $OUT"

if [[ -f /var/lib/olcrtc/features.env ]]; then
  cp -a /var/lib/olcrtc/features.env "$OUT/features.env"
else
  : >"$OUT/features.env"
fi

if [[ -f /etc/olcrtc-manager/deploy-profile.json ]]; then
  cp -a /etc/olcrtc-manager/deploy-profile.json "$OUT/deploy-profile.json"
fi

if [[ -f /etc/olcrtc-manager/panel.env ]]; then
  grep -vE 'PASS|SECRET|TOKEN|OLCRTC_MANAGER_PASS' /etc/olcrtc-manager/panel.env >"$OUT/panel.env.example" || true
fi

systemctl list-unit-files 'olcrtc-*' --no-pager 2>/dev/null | head -50 >"$OUT/systemd-units.txt" || true
df -h / /tmp >"$OUT/df.txt" 2>/dev/null || true
date -u +"%Y-%m-%dT%H:%M:%SZ" >"$OUT/exported-at.txt"
if [[ -d "$REPO_ROOT/.git" ]]; then
  git -C "$REPO_ROOT" log -1 --oneline >"$OUT/olc-cost-l-commit.txt" 2>/dev/null || true
fi
if [[ -f /usr/local/bin/olcrtc-manager ]]; then
  strings /usr/local/bin/olcrtc-manager 2>/dev/null | grep -oE 'index-[A-Za-z0-9_-]+\.js' | head -1 >"$OUT/panel-bundle.txt" || true
fi

log "готово"
