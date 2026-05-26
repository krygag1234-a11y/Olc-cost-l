#!/usr/bin/env bash
# Prerelease-safe GitHub fetch + always show installed release from version.json.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'fetchLatestGitHubReleaseList' "$MAIN_GO" && { echo "[patch-releases-check-v3] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old_fetch = '''func fetchLatestGitHubRelease(ownerRepo string) (tag, name string) {
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
	if tok := githubTokenFromEnv(); tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
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
}'''

new_fetch = '''func githubReleaseRequest(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "olcrtc-manager-panel")
	if tok := githubTokenFromEnv(); tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
	return http.DefaultClient.Do(req)
}

func fetchLatestGitHubReleaseList(ownerRepo string) (tag, name string) {
	if ownerRepo == "" {
		return "", ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	// /releases/latest is empty when all releases are prerelease — use list
	url := "https://api.github.com/repos/" + ownerRepo + "/releases?per_page=5"
	resp, err := githubReleaseRequest(ctx, url)
	if err != nil {
		return "", ""
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", ""
	}
	var list []struct {
		TagName string `json:"tag_name"`
		Name    string `json:"name"`
		Draft   bool   `json:"draft"`
	}
	if json.NewDecoder(resp.Body).Decode(&list) != nil || len(list) == 0 {
		return "", ""
	}
	for _, rel := range list {
		if rel.Draft {
			continue
		}
		tag := strings.TrimSpace(rel.TagName)
		if tag != "" {
			name := strings.TrimSpace(rel.Name)
			if name == "" {
				name = normalizeVerTag(tag)
			}
			return tag, name
		}
	}
	return "", ""
}

func fetchLatestGitHubRelease(ownerRepo string) (tag, name string) {
	return fetchLatestGitHubReleaseList(ownerRepo)
}'''

if old_fetch not in t:
    print("[patch-releases-check-v3] fetchLatestGitHubRelease block not found", file=sys.stderr)
    sys.exit(1)
t = t.replace(old_fetch, new_fetch, 1)

old_compute = '''\trelTag, relName := fetchLatestGitHubRelease(ownerRepo)
\tif relTag == "" {
\t\trelTag, relName = releaseInfoFromVersion(ver)
\t}'''

new_compute = '''\tinstalledTag, installedName := releaseInfoFromVersion(ver)
\trelTag, relName := fetchLatestGitHubRelease(ownerRepo)
\tif relTag == "" && installedTag != "" {
\t\trelTag, relName = installedTag, installedName
\t}'''

if old_compute in t:
    t = t.replace(old_compute, new_compute, 1)

if '"installed_release_tag"' not in t:
    t = t.replace(
        '"latest_release_tag":     relTag,',
        '"installed_release_tag":  installedTag,\n\t\t"latest_release_tag":     relTag,',
        1,
    )

if '"installed_release_tag": upd' not in t and '"latest_release_tag": upd["latest_release_tag"]' in t:
    t = t.replace(
        '"latest_release_tag": upd["latest_release_tag"],',
        '"installed_release_tag": upd["installed_release_tag"],\n\t\t"latest_release_tag": upd["latest_release_tag"],',
        1,
    )

p.write_text(t)
print("[patch-releases-check-v3] ok")
PY
