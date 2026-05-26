#!/usr/bin/env bash
# Updates API, notifications, background jobs, component install/uninstall.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'panelBackendV4' "$MAIN_GO" && { echo "[patch-panel-backend-v4] already applied"; exit 0; }

python3 - "$MAIN_GO" "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path

main_go = Path(sys.argv[1])
repo = Path(sys.argv[2])
t = main_go.read_text()

routes = '''
\thandler.Handle("/api/updates/check", adminAuth(http.HandlerFunc(updatesCheckHandler)))
\thandler.Handle("/api/updates/status", adminAuth(http.HandlerFunc(updatesStatusHandler)))
\thandler.Handle("/api/updates/run", adminAuth(http.HandlerFunc(updatesRunHandler)))
\thandler.Handle("/api/jobs/", adminAuth(panelJobsHandler()))
\thandler.Handle("/api/notifications/scan", adminAuth(http.HandlerFunc(notificationsScanHandler)))
\thandler.Handle("/api/notifications/", adminAuth(http.HandlerFunc(notificationsPatchHandler)))
\thandler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler)))
\thandler.Handle("/api/components/", adminAuth(http.HandlerFunc(componentsActionHandler)))
'''
anchor = '\thandler.Handle("/api/capabilities", adminAuth(http.HandlerFunc(capabilitiesHandler())))'
if 'updatesCheckHandler' not in t:
    t = t.replace(anchor, routes + anchor, 1)

helpers = r'''
// panelBackendV4 — updates, notifications, jobs, component install
const (
	panelUpdateLock  = "/var/lib/olcrtc/panel-update.lock"
	panelUpdateStatus = "/var/lib/olcrtc/panel-update-status.json"
	panelJobsDir     = "/var/lib/olcrtc/panel-jobs"
	panelNotifFile   = "/var/lib/olcrtc/notifications.json"
)

func panelUpdateLocked() bool {
	b, err := os.ReadFile(panelUpdateLock)
	if err != nil {
		return false
	}
	p, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || p <= 0 {
		return false
	}
	proc, err := os.FindProcess(p)
	if err != nil {
		return false
	}
	return proc.Signal(syscall.Signal(0)) == nil
}

func olcRepoRoot() string {
	for _, p := range []string{"/opt/Olc-cost-l", "/opt/olcrtc"} {
		if _, err := os.Stat(filepath.Join(p, "scripts/apply-olcrtc-patches.sh")); err == nil {
			return p
		}
	}
	return "/opt/Olc-cost-l"
}

func runGitShort(repo string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", repo}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func readJSONFile(path string, dest any) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return json.Unmarshal(b, dest) == nil
}

func updatesCheckHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	repo := olcRepoRoot()
	local := runGitShort(repo, "rev-parse", "HEAD")
	_ = runGitShort(repo, "fetch", "origin", "main")
	remote := runGitShort(repo, "rev-parse", "origin/main")
	ver := readVersionJSON()
	writeJSON(w, map[string]any{
		"available":     local != "" && remote != "" && local != remote,
		"local_sha":     local,
		"remote_sha":    remote,
		"panel_version": ver["version"],
		"locked":        panelUpdateLocked(),
	})
}

func updatesStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	out := map[string]any{"locked": panelUpdateLocked()}
	var st map[string]any
	if readJSONFile(panelUpdateStatus, &st) {
		out["job"] = st
	}
	writeJSON(w, out)
}

func updatesRunHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if panelUpdateLocked() {
		http.Error(w, "update already running", http.StatusConflict)
		return
	}
	script := filepath.Join(olcRepoRoot(), "scripts/olc-panel-update-run.sh")
	if _, err := os.Stat(script); err != nil {
		http.Error(w, "update script missing", http.StatusServiceUnavailable)
		return
	}
	jobID := fmt.Sprintf("update-%d", time.Now().Unix())
	cmd := exec.Command("bash", script, jobID)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	if err := cmd.Start(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{"job_id": jobID, "status": "running", "log_path": "/var/log/olcrtc-panel-update.log"})
}

func panelJobsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rest := strings.TrimPrefix(r.URL.Path, "/api/jobs/")
		rest = strings.Trim(rest, "/")
		parts := strings.Split(rest, "/")
		if len(parts) == 0 || parts[0] == "" {
			http.NotFound(w, r)
			return
		}
		jobID := parts[0]
		path := filepath.Join(panelJobsDir, jobID+".json")
		if r.Method == http.MethodGet && len(parts) == 1 {
			var st map[string]any
			if readJSONFile(path, &st) {
				writeJSON(w, st)
				return
			}
			if readJSONFile(panelUpdateStatus, &st) && st["job_id"] == jobID {
				writeJSON(w, st)
				return
			}
			http.NotFound(w, r)
			return
		}
		if r.Method == http.MethodGet && len(parts) == 2 && parts[1] == "log" {
			logPath := "/var/log/olcrtc-panel-update.log"
			var st map[string]any
			if readJSONFile(path, &st) {
				if lp, ok := st["log_path"].(string); ok && lp != "" {
					logPath = lp
				}
			}
			b, err := os.ReadFile(logPath)
			if err != nil {
				http.Error(w, err.Error(), http.StatusNotFound)
				return
			}
			lines := strings.Split(string(b), "\n")
			if len(lines) > 500 {
				lines = lines[len(lines)-500:]
			}
			writeJSON(w, map[string]any{"lines": lines})
			return
		}
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func notificationsListHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var list []map[string]any
	if !readJSONFile(panelNotifFile, &list) {
		list = []map[string]any{}
	}
	unread := 0
	for _, n := range list {
		if read, ok := n["read"].(bool); ok && !read {
			unread++
		}
	}
	writeJSON(w, map[string]any{"notifications": list, "unread": unread})
}

func notificationsScanHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	script := filepath.Join(olcRepoRoot(), "scripts/olc-error-scan.sh")
	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", script)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	_ = cmd.Run()
	var list []map[string]any
	if !readJSONFile(panelNotifFile, &list) {
		list = []map[string]any{}
	}
	writeJSON(w, map[string]any{"notifications": list, "scanned": true})
}

func notificationsPatchHandler(w http.ResponseWriter, r *http.Request) {
	id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/notifications/"), "/")
	if id == "" || id == "scan" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPatch && r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Read     *bool `json:"read"`
		Dismiss  bool  `json:"dismiss"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	var list []map[string]any
	if !readJSONFile(panelNotifFile, &list) {
		list = []map[string]any{}
	}
	statePath := "/var/lib/olcrtc/notifications-state.json"
	var state map[string]any
	readJSONFile(statePath, &state)
	if state == nil {
		state = map[string]any{"seen": map[string]any{}, "dismissed": []any{}}
	}
	dismissed, _ := state["dismissed"].([]any)
	for i, n := range list {
		if n["id"] == id {
			if body.Read != nil {
				list[i]["read"] = *body.Read
			}
			if body.Dismiss {
				if cid, ok := n["catalog_id"].(string); ok {
					dismissed = append(dismissed, cid)
				}
				list = append(list[:i], list[i+1:]...)
			}
			break
		}
	}
	state["dismissed"] = dismissed
	b, _ := json.Marshal(list)
	_ = os.WriteFile(panelNotifFile, b, 0644)
	sb, _ := json.Marshal(state)
	_ = os.WriteFile(statePath, sb, 0644)
	writeJSON(w, map[string]string{"status": "ok"})
}

func componentsActionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if panelUpdateLocked() {
		http.Error(w, "panel update in progress", http.StatusConflict)
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/components/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) < 2 {
		http.Error(w, "expected /api/components/{name}/{install|uninstall}", http.StatusBadRequest)
		return
	}
	name, action := parts[0], parts[1]
	allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true}
	if !allowed[name] || (action != "install" && action != "uninstall") {
		http.Error(w, "unknown component or action", http.StatusBadRequest)
		return
	}
	script := filepath.Join(olcRepoRoot(), "scripts/olc-component-job.sh")
	jobID := fmt.Sprintf("%s-%s-%d", name, action, time.Now().Unix())
	cmd := exec.Command("bash", script, name, action, jobID)
	cmd.Env = append(os.Environ(), "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin")
	if err := cmd.Start(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{
		"job_id": jobID, "component": name, "action": action, "status": "running",
		"log_path": fmt.Sprintf("/var/log/olcrtc-component-%s-%s.log", name, action),
	})
}

'''

# imports
blk = t.split("import (")[1].split(")")[0]
for imp, needle, insert in (
    ('"syscall"', '"time"\n', '"time"\n\t"syscall"\n'),
    ('"strconv"', '"strings"\n', '"strings"\n\t"strconv"\n'),
    ('"path/filepath"', '"os"\n', '"os"\n\t"path/filepath"\n'),
):
    if imp not in blk:
        t = t.replace(needle, insert, 1)

if 'func updatesCheckHandler' not in t:
    t = t.rstrip() + "\n" + helpers

main_go.write_text(t)
print("[patch-panel-backend-v4] ok")
PY

chmod +x "$REPO_ROOT/scripts/olc-panel-update-run.sh" \
  "$REPO_ROOT/scripts/olc-error-scan.sh" \
  "$REPO_ROOT/scripts/olc-component-job.sh" 2>/dev/null || true
