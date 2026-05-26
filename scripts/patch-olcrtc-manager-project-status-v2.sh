#!/usr/bin/env bash
# Project status: component stack 4/5 instead of patch script count.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'componentStackStatus' "$MAIN_GO" && { echo "[patch-project-status-v2] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helper = r'''
func componentStackStatus() map[string]any {
	flags := readFeatureFlags()
	installed := map[string]bool{
		"zapret":  componentInstalled("zapret"),
		"tor":     componentInstalled("tor"),
		"split":   componentInstalled("split"),
		"bridges": componentInstalled("bridges"),
	}
	labels := map[string]string{
		"zapret": "Zapret", "tor": "Tor", "split": "Split", "bridges": "Мосты",
	}
	optional := []string{"warp"}
	on := 0
	total := 0
	items := []map[string]any{}
	for _, id := range []string{"zapret", "tor", "split", "bridges"} {
		total++
		enabled := flags[id]
		if enabled {
			on++
		}
		items = append(items, map[string]any{
			"id": id, "label": labels[id], "enabled": enabled, "installed": installed[id],
		})
	}
	for _, id := range optional {
		items = append(items, map[string]any{
			"id": id, "label": "WARP", "enabled": flags[id], "installed": componentInstalled("warp"), "optional": true,
		})
	}
	return map[string]any{
		"enabled": on, "total": total, "items": items,
		"note": "Сервисы стека Olc-cost-l (Zapret, Tor, Split, Мосты). WARP — опционально.",
	}
}

'''

if 'func componentStackStatus' not in t:
    t = t.replace('func projectStatusHandler(w http.ResponseWriter', helper + 'func projectStatusHandler(w http.ResponseWriter', 1)

old = '''	patchTotal := countPatchScripts(repo)
	// Heuristic: manager binary mtime + repo presence
	patchApplied := patchTotal
	if _, err := os.Stat("/usr/local/bin/olcrtc-manager"); err != nil {
		patchApplied = 0
	}

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
if old in t:
    t = t.replace(old, new, 1)

t = t.replace(
    '''		"patches": map[string]any{
			"total_scripts": patchTotal,
			"applied_estimate": patchApplied,
		},''',
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

p.write_text(t)
print("[patch-project-status-v2] ok")
PY
