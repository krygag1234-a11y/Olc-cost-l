#!/usr/bin/env bash
# GitHub Releases check + sane git behind/ahead for update_available.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'computeUpdateStatus' "$MAIN_GO" && { echo "[patch-releases-check] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

main_go = Path(sys.argv[1])
t = main_go.read_text()

helpers = r'''
func normalizeVerTag(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(strings.ToLower(s), "v")
	return s
}

func versionNewer(current, latest string) bool {
	c := normalizeVerTag(current)
	l := normalizeVerTag(latest)
	if c == "" || l == "" || c == l {
		return false
	}
	if strings.Contains(c, "-alpha.") && strings.Contains(l, "-alpha.") {
		cp := strings.SplitN(c, "-alpha.", 2)
		lp := strings.SplitN(l, "-alpha.", 2)
		if len(cp) == 2 && len(lp) == 2 && cp[0] == lp[0] {
			return cp[1] < lp[1]
		}
	}
	return strings.Compare(l, c) > 0
}

func githubRepoFromVersion(ver map[string]any) string {
	raw, _ := ver["repo"].(string)
	raw = strings.TrimSpace(raw)
	raw = strings.TrimPrefix(raw, "https://github.com/")
	raw = strings.TrimPrefix(raw, "http://github.com/")
	return strings.TrimSuffix(raw, "/")
}

func gitIsAncestor(repo, older, newer string) bool {
	if repo == "" || older == "" || newer == "" || older == newer {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", "-c", "safe.directory="+repo, "-C", repo, "merge-base", "--is-ancestor", older, newer)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	return cmd.Run() == nil
}

func gitLocalBehindRemote(repo, local, remote string) bool {
	return gitIsAncestor(repo, local, remote) && local != remote
}

func gitLocalAheadOfRemote(repo, local, remote string) bool {
	return gitIsAncestor(repo, remote, local) && local != remote
}

func fetchLatestGitHubRelease(ownerRepo string) (tag, name string) {
	if ownerRepo == "" {
		return "", ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.github.com/repos/"+ownerRepo+"/releases/latest", nil)
	if err != nil {
		return "", ""
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "olcrtc-manager-panel")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", ""
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", ""
	}
	var rel struct {
		TagName string `json:"tag_name"`
		Name    string `json:"name"`
	}
	if json.NewDecoder(resp.Body).Decode(&rel) != nil {
		return "", ""
	}
	return strings.TrimSpace(rel.TagName), strings.TrimSpace(rel.Name)
}

func computeUpdateStatus(repo string) map[string]any {
	ver := readVersionJSON()
	panelVer, _ := ver["panel"].(string)
	ownerRepo := githubRepoFromVersion(ver)
	_ = runGitShort(repo, "fetch", "origin", "main")
	local := runGitShort(repo, "rev-parse", "HEAD")
	remote := runGitShort(repo, "rev-parse", "origin/main")
	relTag, relName := fetchLatestGitHubRelease(ownerRepo)
	gitBehind := gitLocalBehindRemote(repo, local, remote)
	gitAhead := gitLocalAheadOfRemote(repo, local, remote)
	releaseNewer := relTag != "" && panelVer != "" && versionNewer(panelVer, relTag)
	updateAvailable := releaseNewer || gitBehind
	updateSource := "none"
	if releaseNewer {
		updateSource = "release"
	} else if gitBehind {
		updateSource = "git"
	}
	return map[string]any{
		"local_sha":              local,
		"remote_sha":             remote,
		"panel_version":          panelVer,
		"latest_release_tag":     relTag,
		"latest_release_name":    relName,
		"latest_release_version": normalizeVerTag(relTag),
		"update_available":       updateAvailable,
		"update_source":          updateSource,
		"git_behind":             gitBehind,
		"git_ahead":              gitAhead,
	}
}

'''

anchor = "func readVersionJSON()"
if anchor not in t:
    print("[patch-releases-check] readVersionJSON not found", file=sys.stderr)
    sys.exit(1)
t = t.replace(anchor, helpers + anchor, 1)

for imp in ("context", "net/http", "os/exec", "time"):
    if f'"{imp}"' not in t:
        m = re.search(r"import \(\n", t)
        if m:
            t = t[: m.end()] + f'\t"{imp}"\n' + t[m.end() :]

old_updates = r'''func updatesCheckHandler(w http.ResponseWriter, r *http.Request) {
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
}'''

new_updates = r'''func updatesCheckHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	repo := olcRepoRoot()
	st := computeUpdateStatus(repo)
	st["available"] = st["update_available"]
	st["locked"] = panelUpdateLocked()
	writeJSON(w, st)
}'''

if old_updates in t:
    t = t.replace(old_updates, new_updates, 1)
else:
    print("[patch-releases-check] updatesCheckHandler block not found", file=sys.stderr)

old_project = r'''	repo := olcRepoRoot()
	local := runGitShort(repo, "rev-parse", "HEAD")
	remote := runGitShort(repo, "rev-parse", "origin/main")
	if remote == "" {
		_ = runGitShort(repo, "fetch", "origin", "main")
		remote = runGitShort(repo, "rev-parse", "origin/main")
	}
	ver := readVersionJSON()'''

new_project = r'''	repo := olcRepoRoot()
	upd := computeUpdateStatus(repo)
	local, _ := upd["local_sha"].(string)
	remote, _ := upd["remote_sha"].(string)
	ver := readVersionJSON()'''

if old_project in t:
    t = t.replace(old_project, new_project, 1)
else:
    print("[patch-releases-check] projectStatusHandler git block not found", file=sys.stderr)

old_avail = '"update_available": local != "" && remote != "" && local != remote,'
new_avail = '''"update_available":   upd["update_available"],
		"update_source":      upd["update_source"],
		"git_behind":         upd["git_behind"],
		"git_ahead":          upd["git_ahead"],
		"latest_release_tag": upd["latest_release_tag"],
		"latest_release_name": upd["latest_release_name"],'''
if old_avail in t:
    t = t.replace(old_avail, new_avail, 1)

main_go.write_text(t)
print("[patch-releases-check] ok")
PY
