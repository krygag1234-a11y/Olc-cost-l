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
      log "$f: совпадает с golden baseline"
    else
      log "$f: ожидаемо изменён финальными patch-скриптами после golden baseline"
    fi
  fi
done

# Exact equality with golden is not expected: apply_manager deliberately runs
# ordered final patches after apply-golden-panel.sh. Verify their contracts.
declare -a required_markers=(
  "$MGR_REPO/src/main.tsx|OLC_MANAGER_UPSTREAM_FOLLOWUP_V1"
  "$MGR_REPO/src/main.tsx|OLC_JITSI_HTTPS_DISCOVERY_UI_V1"
  "$MGR_REPO/src/main.tsx|OLC_PROXY_POLICY_UI_V1"
  "$MGR_REPO/src/main.tsx|OLC_TOGGLE_BUTTONS_UI_V4"
  "$MGR_REPO/src/main.tsx|OLC_TOGGLE_TARGETED_LAYOUT_V1"
  "$MGR_REPO/src/main.tsx|OLC_DEFAULTS_AUTOSAVE_CRUD_V1"
  "$MGR_REPO/src/main.tsx|olc-plain-enter-blur"
  "$MGR_REPO/cmd/olcrtc-manager/main.go|OLC_MANAGER_UPSTREAM_FOLLOWUP_V1"
  "$MGR_REPO/cmd/olcrtc-manager/main.go|olc-jitsi-https-discovery-v1"
  "$MGR_REPO/cmd/olcrtc-manager/main.go|OLC_PROXY_POLICY_V1"
  "$MGR_REPO/cmd/olcrtc-manager/main.go|Current peers count:"
  "$MGR_REPO/cmd/olcrtc-manager/main.go|device_labels,omitempty"
)
for item in "${required_markers[@]}"; do
  file="${item%%|*}"
  marker="${item#*|}"
  if grep -Fq "$marker" "$file" 2>/dev/null; then
    log "marker: ok — $marker"
  else
    log "marker: FAIL — $marker"
    fail=1
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
log "FAIL — нарушен golden/final patch contract"
exit 1
