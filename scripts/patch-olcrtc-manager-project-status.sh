#!/usr/bin/env bash
# GET /api/project/status — dashboard for «Проект» modal.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'projectStatusHandler' "$MAIN_GO" && { echo "[patch-project-status] already applied"; exit 0; }

python3 - "$MAIN_GO" "$REPO_ROOT" <<'PY'
import json
import sys
from pathlib import Path

p = Path(sys.argv[1])
repo = Path(sys.argv[2])
t = p.read_text()

route = '\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))\n'
anchor = '\thandler.Handle("/api/updates/check", adminAuth(http.HandlerFunc(updatesCheckHandler)))'
if 'projectStatusHandler' not in t:
    t = t.replace(anchor, route + anchor, 1)

helpers = r'''
func countPatchScripts(repo string) int {
	n := 0
	dir := filepath.Join(repo, "scripts")
	ents, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if strings.HasPrefix(name, "patch-olcrtc") && strings.HasSuffix(name, ".sh") {
			n++
		}
	}
	return n
}

func readPins(repo string) map[string]any {
	out := map[string]any{}
	path := filepath.Join(repo, "data/upstream-pins.json")
	b, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	_ = json.Unmarshal(b, &out)
	return out
}

func notificationStats() map[string]any {
	st := map[string]any{"total": 0, "unread": 0, "errors": 0, "warnings": 0}
	var list []map[string]any
	if readJSONFile(panelNotifFile, &list) {
		st["total"] = len(list)
		for _, n := range list {
			if read, ok := n["read"].(bool); ok && !read {
				st["unread"] = st["unread"].(int) + 1
			}
			switch n["severity"] {
			case "error":
				st["errors"] = st["errors"].(int) + 1
			case "warning":
				st["warnings"] = st["warnings"].(int) + 1
			}
		}
	}
	return st
}

func projectStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	repo := olcRepoRoot()
	local := runGitShort(repo, "rev-parse", "HEAD")
	remote := runGitShort(repo, "rev-parse", "origin/main")
	if remote == "" {
		_ = runGitShort(repo, "fetch", "origin", "main")
		remote = runGitShort(repo, "rev-parse", "origin/main")
	}
	ver := readVersionJSON()
	pins := readPins(repo)
	notif := notificationStats()
	locked := panelUpdateLocked()
	var updateJob map[string]any
	readJSONFile(panelUpdateStatus, &updateJob)

	patchTotal := countPatchScripts(repo)
	// Heuristic: manager binary mtime + repo presence
	patchApplied := patchTotal
	if _, err := os.Stat("/usr/local/bin/olcrtc-manager"); err != nil {
		patchApplied = 0
	}

	writeJSON(w, map[string]any{
		"panel_version":   ver["panel"],
		"channel":         ver["channel"],
		"repo_path":       repo,
		"local_sha":       local,
		"remote_sha":      remote,
		"update_available": local != "" && remote != "" && local != remote,
		"update_locked":   locked,
		"update_job":      updateJob,
		"deploy_profile":  readDeployProfileID(),
		"patches": map[string]any{
			"total_scripts": patchTotal,
			"applied_estimate": patchApplied,
		},
		"upstream_pins": pins,
		"capabilities": map[string]any{
			"components": map[string]bool{
				"zapret":  componentInstalled("zapret"),
				"tor":     componentInstalled("tor"),
				"split":   componentInstalled("split"),
				"bridges": componentInstalled("bridges"),
			},
			"flags": readFeatureFlags(),
		},
		"notifications": notif,
		"manager": map[string]any{
			"pid": os.Getpid(),
		},
	})
}

'''

if 'func projectStatusHandler' not in t:
    t = t.rstrip() + "\n" + helpers

p.write_text(t)
print("[patch-project-status] ok")
PY
