#!/usr/bin/env bash
# Split toggle: setup-split-ru may exit non-zero while still writing lists — don't 500 the API.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'featuresSplitTolerant' "$MAIN_GO" && { echo "[patch-features-tolerant] already applied"; exit 0; }
grep -q 'featuresToggleHandler' "$MAIN_GO" || exit 0

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
if "split on may warn in setup-split-ru" in t:
    print("[patch-features-tolerant] already patched")
    raise SystemExit(0)
old = """\t\tif err != nil {
\t\t\tresult[\"error\"] = err.Error()
\t\t\tw.WriteHeader(http.StatusInternalServerError)
\t\t}
\t\twriteJSON(w, result)"""
new = """\t\tif err != nil {
\t\t\tresult[\"error\"] = err.Error()
\t\t\t// split on may warn in setup-split-ru but still enable routing lists
\t\t\tif !(name == \"split\" && body.Enabled && readFeatureFlags()[\"split\"]) {
\t\t\t\tw.WriteHeader(http.StatusInternalServerError)
\t\t\t}
\t\t}
\t\twriteJSON(w, result)"""
if old not in t:
    raise SystemExit("[patch-features-tolerant] toggle handler block not found")
p.write_text(t.replace(old, new, 1))
print("[patch-features-tolerant] ok")
PY
