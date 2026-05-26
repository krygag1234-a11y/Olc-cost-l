#!/usr/bin/env bash
# Release from version.json stack + GitHub API with optional token; stale update reconcile.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'releaseInfoFromVersion' "$MAIN_GO" && { echo "[patch-releases-check-v2] already applied"; exit 0; }
grep -q 'computeUpdateStatus' "$MAIN_GO" || { echo "[patch-releases-check-v2] need v1"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

extra = r'''
func githubTokenFromEnv() string {
	for _, key := range []string{"GITHUB_TOKEN", "GH_TOKEN", "OLCRTC_GITHUB_TOKEN"} {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			return v
		}
	}
	for _, path := range []string{"/etc/olcrtc-manager/github.env", "/etc/olcrtc-manager/panel.env"} {
		b, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if strings.HasPrefix(line, "export ") {
				line = strings.TrimPrefix(line, "export ")
			}
			parts := strings.SplitN(line, "=", 2)
			if len(parts) != 2 {
				continue
			}
			k := strings.TrimSpace(parts[0])
			v := strings.Trim(strings.TrimSpace(parts[1]), `"'`)
			if k == "GITHUB_TOKEN" || k == "GH_TOKEN" || k == "OLCRTC_GITHUB_TOKEN" {
				return v
			}
		}
	}
	return ""
}

func releaseInfoFromVersion(ver map[string]any) (tag, name string) {
	rel, _ := ver["release"].(map[string]any)
	if rel == nil {
		return "", ""
	}
	tag, _ = rel["tag"].(string)
	tag = strings.TrimSpace(tag)
	if tag == "" {
		return "", ""
	}
	return tag, normalizeVerTag(tag)
}

func reconcileStaleUpdateJob() {
	if panelUpdateLocked() {
		return
	}
	var st map[string]any
	if !readJSONFile(panelUpdateStatus, &st) {
		return
	}
	if st["status"] != "running" {
		return
	}
	st["status"] = "failed"
	st["error"] = "зависло (процесс обновления прерван) — повторите «Обновить с GitHub»"
	st["exit_code"] = 1
	b, _ := json.Marshal(st)
	_ = os.WriteFile(panelUpdateStatus, b, 0644)
}

'''

if "func githubTokenFromEnv" not in t:
    t = t.replace("func normalizeVerTag(s string)", extra + "func normalizeVerTag(s string)", 1)

t = t.replace(
    '''\treq.Header.Set("Accept", "application/vnd.github+json")
\treq.Header.Set("User-Agent", "olcrtc-manager-panel")
\tresp, err := http.DefaultClient.Do(req)''',
    '''\treq.Header.Set("Accept", "application/vnd.github+json")
\treq.Header.Set("User-Agent", "olcrtc-manager-panel")
\tif tok := githubTokenFromEnv(); tok != "" {
\t\treq.Header.Set("Authorization", "Bearer "+tok)
\t}
\tresp, err := http.DefaultClient.Do(req)''',
    1,
)

t = t.replace(
    '''\trelTag, relName := fetchLatestGitHubRelease(ownerRepo)
\tgitBehind := gitLocalBehindRemote(repo, local, remote)''',
    '''\trelTag, relName := fetchLatestGitHubRelease(ownerRepo)
\tif relTag == "" {
\t\trelTag, relName = releaseInfoFromVersion(ver)
\t}
\tgitBehind := gitLocalBehindRemote(repo, local, remote)''',
    1,
)

if "reconcileStaleUpdateJob()" not in t:
    t = t.replace(
        "func projectStatusHandler(w http.ResponseWriter, r *http.Request) {",
        "func projectStatusHandler(w http.ResponseWriter, r *http.Request) {\n\treconcileStaleUpdateJob()",
        1,
    )
    t = t.replace(
        "func updatesCheckHandler(w http.ResponseWriter, r *http.Request) {",
        "func updatesCheckHandler(w http.ResponseWriter, r *http.Request) {\n\treconcileStaleUpdateJob()",
        1,
    )

# expose stack in project status
if '"stack_manifest"' not in t and "ver := readVersionJSON()" in t and "projectStatusHandler" in t:
    t = t.replace(
        '''\tver := readVersionJSON()
\tpins := readPins(repo)''',
        '''\tver := readVersionJSON()
\tstackManifest, _ := ver["stack"].(map[string]any)
\tpins := readPins(repo)''',
        1,
    )
    t = t.replace(
        '"channel":         ver["channel"],',
        '"channel":         ver["channel"],\n\t\t"stack_manifest":  stackManifest,',
        1,
    )

p.write_text(t)
print("[patch-releases-check-v2] ok")
PY
