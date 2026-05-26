#!/usr/bin/env bash
# Components jobs API: list component jobs for persistent UI status.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'func componentsJobsHandler' "$MAIN_GO" && { echo "[patch-components-jobs-v2] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if '/api/components/jobs' not in t:
    t = t.replace(
        '\thandler.Handle("/api/jobs/", adminAuth(panelJobsHandler()))\n',
        '\thandler.Handle("/api/jobs/", adminAuth(panelJobsHandler()))\n\thandler.Handle("/api/components/jobs", adminAuth(http.HandlerFunc(componentsJobsHandler)))\n',
        1,
    )

helper = r'''
func componentsJobsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	componentFilter := strings.TrimSpace(r.URL.Query().Get("component"))
	type item struct {
		mod time.Time
		st  map[string]any
	}
	glob := filepath.Join(panelJobsDir, "*.json")
	files, _ := filepath.Glob(glob)
	out := []item{}
	for _, p := range files {
		info, err := os.Stat(p)
		if err != nil || info.IsDir() {
			continue
		}
		var st map[string]any
		if !readJSONFile(p, &st) {
			continue
		}
		if typ, _ := st["type"].(string); typ != "component" {
			continue
		}
		if componentFilter != "" {
			if c, _ := st["component"].(string); c != componentFilter {
				continue
			}
		}
		if _, ok := st["job_id"]; !ok {
			st["job_id"] = strings.TrimSuffix(filepath.Base(p), ".json")
		}
		out = append(out, item{mod: info.ModTime(), st: st})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].mod.After(out[j].mod) })
	jobs := make([]map[string]any, 0, len(out))
	for _, it := range out {
		jobs = append(jobs, it.st)
	}
	writeJSON(w, map[string]any{"jobs": jobs})
}

'''

if 'func componentsJobsHandler' not in t:
    t = t.replace('func notificationsListHandler(w http.ResponseWriter, r *http.Request) {', helper + 'func notificationsListHandler(w http.ResponseWriter, r *http.Request) {', 1)

p.write_text(t)
print("[patch-components-jobs-v2] ok")
PY
