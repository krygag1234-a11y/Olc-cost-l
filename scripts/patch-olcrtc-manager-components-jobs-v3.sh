#!/usr/bin/env bash
# Component jobs API: hide finished jobs older than 3 minutes.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'componentJobStale' "$MAIN_GO" && { echo "[patch-components-jobs-v3] already applied"; exit 0; }
grep -q 'func componentsJobsHandler' "$MAIN_GO" || { echo "[patch-components-jobs-v3] need v2"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helper = r'''
func componentJobStale(st map[string]any, mod time.Time) bool {
	status, _ := st["status"].(string)
	if status != "done" && status != "failed" {
		return false
	}
	if raw, ok := st["finished_at"].(string); ok && raw != "" {
		if ts, err := time.Parse(time.RFC3339, raw); err == nil {
			return time.Since(ts) > 3*time.Minute
		}
	}
	return time.Since(mod) > 3*time.Minute
}

'''

if "func componentJobStale" not in t:
    t = t.replace("func componentsJobsHandler(w http.ResponseWriter, r *http.Request) {", helper + "func componentsJobsHandler(w http.ResponseWriter, r *http.Request) {", 1)

old = '''		out = append(out, item{mod: info.ModTime(), st: st})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].mod.After(out[j].mod) })'''

new = '''		if componentJobStale(st, info.ModTime()) {
			continue
		}
		if status, _ := st["status"].(string); (status == "done" || status == "failed") && st["finished_at"] == nil {
			st["finished_at"] = info.ModTime().Format(time.RFC3339)
		}
		out = append(out, item{mod: info.ModTime(), st: st})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].mod.After(out[j].mod) })'''

if old not in t:
    print("[patch-components-jobs-v3] anchor not found", file=sys.stderr)
    sys.exit(1)
t = t.replace(old, new, 1)
p.write_text(t)
print("[patch-components-jobs-v3] ok")
PY
