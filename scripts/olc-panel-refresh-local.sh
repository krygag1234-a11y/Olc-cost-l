#!/usr/bin/env bash
# Применить packaging/golden-panel на ЭТОМ VPS и пересобрать olcrtc-manager (без полного install).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MGR_REPO="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}"

[[ "$(id -u)" -eq 0 ]] || { echo "[panel-refresh] нужен root (sudo)" >&2; exit 1; }

log() { echo "[panel-refresh] $*"; }

if [[ ! -d "$MGR_REPO/.git" ]]; then
  log "клон manager panel…"
  git clone --depth 1 https://github.com/BigDaddy3334/olcrtc-manager-panel.git "$MGR_REPO"
fi

if [[ ! -f "$MGR_REPO/cmd/olcrtc-manager/main.go" ]]; then
  log "WARN: битый clone — переклонируем"
  rm -rf "$MGR_REPO"
  git clone --depth 1 https://github.com/BigDaddy3334/olcrtc-manager-panel.git "$MGR_REPO"
fi

# shellcheck source=lib-disk-preflight.sh
source "$SCRIPT_DIR/lib-disk-preflight.sh"
olc_preflight_disk_space "пересборка панели" || exit 1

log "golden overlay + postcss + сборка"
bash "$SCRIPT_DIR/apply-golden-panel.sh" "$MGR_REPO"
bash "$SCRIPT_DIR/patch-olcrtc-manager-postcss.sh" "$MGR_REPO"

if ! command -v npm >/dev/null 2>&1; then
  log "ОШИБКА: нужен npm (nodejs). Запустите install.sh --update или apt install nodejs npm"
  exit 1
fi

(cd "$MGR_REPO" && npm ci 2>/dev/null || npm install)
(cd "$MGR_REPO" && npm run build)

export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
(cd "$MGR_REPO" && go build -o /usr/local/bin/olcrtc-manager ./cmd/olcrtc-manager/)
systemctl restart olcrtc-manager 2>/dev/null || true

if [[ -f /etc/olcrtc-manager/deploy-profile.json ]] \
  && command -v jq >/dev/null 2>&1 \
  && [[ "$(jq -r '.panel.access // "ip"' /etc/olcrtc-manager/deploy-profile.json 2>/dev/null || echo ip)" == "ssh" ]]; then
  log "готово. Проверка: http://127.0.0.1:8888/admin (через SSH-туннель)"
else
  log "готово. Проверка: http://$(hostname -I | awk '{print $1}'):8888/admin"
fi
if grep -q videochannel "$MGR_REPO/src/main.tsx" 2>/dev/null; then
  log "WARN: в main.tsx всё ещё есть videochannel"
else
  log "videochannel в UI: нет"
fi
