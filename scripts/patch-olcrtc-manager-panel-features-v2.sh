#!/usr/bin/env bash
# Upgrade Features panel: Russian labels + logs hint (idempotent).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'FeaturesPanelV2' "$MAIN_TSX" && { echo "[patch-panel-features-v2] already applied"; exit 0; }
grep -q 'FeaturesPanel' "$MAIN_TSX" || { echo "[patch-panel-features-v2] skip: no FeaturesPanel"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

t = t.replace(
    '<h2 className="text-lg font-semibold tracking-normal">Network features</h2>',
    '<h2 className="text-lg font-semibold tracking-normal">Сеть и обход</h2>',
    1,
)
t = t.replace(
    'On/off для zapret · tor · split · webtunnel без переустановки. State пишется в /etc/olcrtc-manager/features.env.',
    'Вкл/выкл zapret · tor · split · webtunnel без переустановки. Состояние: /etc/olcrtc-manager/features.env. '
    'Логи клиента: раздел «Клиенты» → Logs (API /api/logs). Jitsi TLS: OLCRTC_JITSI_INSECURE_TLS=1 в panel.env.',
    1,
)
t = t.replace('{busy === row.name ? "…" : enabled ? "Disable" : "Enable"}',
              '{busy === row.name ? "…" : enabled ? "Выключить" : "Включить"}', 1)

# marker comment inside component
t = t.replace("function FeaturesPanel() {", "function FeaturesPanel() { // FeaturesPanelV2", 1)

p.write_text(t)
print("[patch-panel-features-v2] ok"); raise SystemExit(0)
PY
