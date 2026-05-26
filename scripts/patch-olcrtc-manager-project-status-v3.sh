#!/usr/bin/env bash
# Restore patches counters alongside stack in /api/project/status.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'patchTotal := countPatchScripts' "$MAIN_GO" \
  && grep -q 'componentInstalled("warp")' "$MAIN_GO" \
  && { echo "[patch-project-status-v3] already applied"; exit 0; }
grep -q 'componentStackStatus' "$MAIN_GO" || { echo "[patch-project-status-v3] skip (need v2)"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
old = '''	stack := componentStackStatus()

	writeJSON(w, map[string]any{
'''
new = '''	stack := componentStackStatus()
	patchTotal := countPatchScripts(repo)
	patchApplied := patchTotal
	if _, err := os.Stat("/usr/local/bin/olcrtc-manager"); err != nil {
		patchApplied = 0
	}

	writeJSON(w, map[string]any{
'''
if old not in t:
    print("[patch-project-status-v3] anchor not found", file=sys.stderr)
    sys.exit(1)
t = t.replace(old, new, 1)
t = t.replace(
    '''		"stack": stack,
		"patches": stack,''',
    '''		"stack": stack,
		"patches": map[string]any{
			"total_scripts":    patchTotal,
			"applied_estimate": patchApplied,
			"enabled":          stack["enabled"],
			"total":            stack["total"],
			"items":            stack["items"],
		},''',
    1,
)
t = t.replace(
    '"installed": false, "optional": true',
    '"installed": componentInstalled("warp"), "optional": true',
    1,
)
p.write_text(t)
print("[patch-project-status-v3] ok")
PY
