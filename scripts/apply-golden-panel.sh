#!/usr/bin/env bash
# Копирует эталон панели с рабочего тестового VPS (packaging/golden-panel/).
# Вызывается в конце apply-olcrtc-patches.sh — выравнивает UI/Go с эталоном.
#
# Флаги:
#   OLCRTC_FORCE_SHA_UPDATE=1  - автообновление SHA256SUMS при несовпадении
#   OLC_AUTO_SHA_UPDATE=1      - то же самое (алиас)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GOLDEN_DIR="${OLC_GOLDEN_PANEL_DIR:-$REPO_ROOT/packaging/golden-panel}"
MGR_REPO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}}"

log() { echo "[golden-panel] $*"; }

[[ -f "$GOLDEN_DIR/main.tsx" && -f "$GOLDEN_DIR/main.go" ]] || {
  log "ОШИБКА: нет $GOLDEN_DIR/main.tsx или main.go — обновите эталон с тестового VPS"
  exit 1
}

if [[ -f "$GOLDEN_DIR/SHA256SUMS" ]]; then
  if ! (cd "$GOLDEN_DIR" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
    log "WARN: checksum эталона не совпадает (main.go/main.tsx изменены)"
    (cd "$GOLDEN_DIR" && sha256sum -c SHA256SUMS 2>&1 | sed 's/^/  /') || true
    
    if [[ "${OLCRTC_FORCE_SHA_UPDATE:-0}" == "1" || "${OLC_AUTO_SHA_UPDATE:-0}" == "1" ]]; then
      log "автообновление SHA256SUMS (OLCRTC_FORCE_SHA_UPDATE=1)"
      (cd "$GOLDEN_DIR" && sha256sum main.go main.tsx > SHA256SUMS)
      log "SHA256SUMS обновлён — не забудьте git commit"
    else
      log "ОШИБКА: checksum не совпадает. Для автообновления: OLCRTC_FORCE_SHA_UPDATE=1"
      log "  cd $GOLDEN_DIR && sha256sum main.go main.tsx > SHA256SUMS && git add SHA256SUMS && git commit"
      exit 1
    fi
  fi
fi

[[ -d "$MGR_REPO/src" ]] || { log "ОШИБКА: нет $MGR_REPO/src"; exit 1; }
install -d "$MGR_REPO/cmd/olcrtc-manager"

cp -f "$GOLDEN_DIR/main.tsx" "$MGR_REPO/src/main.tsx"
cp -f "$GOLDEN_DIR/main.go" "$MGR_REPO/cmd/olcrtc-manager/main.go"
chmod 644 "$MGR_REPO/src/main.tsx" "$MGR_REPO/cmd/olcrtc-manager/main.go"

log "ok: main.tsx + main.go ← $GOLDEN_DIR (эталон тестового VPS)"
