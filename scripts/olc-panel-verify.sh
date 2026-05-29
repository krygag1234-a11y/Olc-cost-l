#!/usr/bin/env bash
# Сравнение собранной панели с эталоном (после apply-golden-panel + npm build).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GOLDEN_DIR="${OLC_GOLDEN_PANEL_DIR:-$REPO_ROOT/packaging/golden-panel}"
MGR_REPO="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}"
EXPECTED_JS="${OLC_GOLDEN_JS:-index-BgVOK4FZ.js}"

fail=0
log() { echo "[panel-verify] $*"; }

if [[ -f "$GOLDEN_DIR/SHA256SUMS" ]]; then
  if (cd "$GOLDEN_DIR" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
    log "эталон SHA256: ok"
  else
    log "эталон SHA256: FAIL"
    fail=1
  fi
fi

for f in main.tsx main.go; do
  if [[ ! -f "$MGR_REPO/src/main.tsx" && "$f" == main.tsx ]]; then continue; fi
  case "$f" in
    main.tsx) dst="$MGR_REPO/src/main.tsx" ;;
    main.go) dst="$MGR_REPO/cmd/olcrtc-manager/main.go" ;;
  esac
  if [[ -f "$dst" && -f "$GOLDEN_DIR/$f" ]]; then
    if cmp -s "$GOLDEN_DIR/$f" "$dst"; then
      log "$f: совпадает с эталоном"
    else
      log "$f: ОТЛИЧАЕТСЯ от эталона (нужен apply-golden-panel.sh?)"
      fail=1
    fi
  fi
done

dist="$MGR_REPO/cmd/olcrtc-manager/web/dist/assets"
if [[ -d "$dist" ]]; then
  js="$(ls "$dist"/index-*.js 2>/dev/null | head -1)"
  if [[ -n "$js" ]]; then
    log "bundle: $(basename "$js") (ожидаемый эталон с тест VPS: $EXPECTED_JS)"
    if [[ "$(basename "$js")" != "$EXPECTED_JS" ]]; then
      log "имя bundle другое — нормально при другом vite hash; сверяйте поведение UI вручную"
    fi
  else
    log "bundle: не найден — сначала npm run build"
    fail=1
  fi
else
  log "web/dist: нет — сначала npm run build"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  log "OK"
  exit 0
fi
log "FAIL — панель не совпадает с эталоном"
exit 1
