#!/usr/bin/env bash
# Conservative VP8/SEI defaults — Telemost flaps ICE above ~55 fps/batch (user + goolom limits).
set -euo pipefail
PANEL="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$PANEL" ]] || exit 0

python3 - "$PANEL" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

replacements = [
    ('{ key: "vp8-fps", label: "FPS", defaultValue: "60" }', '{ key: "vp8-fps", label: "FPS", defaultValue: "50" }'),
    ('{ key: "vp8-batch", label: "Batch", defaultValue: "64" }', '{ key: "vp8-batch", label: "Batch", defaultValue: "50" }'),
    ('{ key: "fps", label: "FPS", defaultValue: "60" }', '{ key: "fps", label: "FPS", defaultValue: "50" }'),
    ('{ key: "batch", label: "Batch", defaultValue: "64" }', '{ key: "batch", label: "Batch", defaultValue: "50" }'),
]
for old, new in replacements:
    if old in t:
        t = t.replace(old, new, 1)

p.write_text(t)
print("[patch-panel-vp8-defaults] ok (50/50 defaults)"); raise SystemExit(0)
PY
