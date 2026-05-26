#!/usr/bin/env bash
# Git safe.directory for olcrtc-manager (runs as root, repo may be owned by deploy user).
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'safe.directory=' "$MAIN_GO" && { echo "[patch-git-safe-dir] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
patterns = [
    (
        '''func runGitShort(repo string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", repo}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}''',
        '''func runGitShort(repo string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	gitArgs := []string{"-c", "safe.directory=" + repo, "-C", repo}
	gitArgs = append(gitArgs, args...)
	cmd := exec.CommandContext(ctx, "git", gitArgs...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}''',
    ),
]
for old, new in patterns:
    if old in t:
        p.write_text(t.replace(old, new, 1))
        print("[patch-git-safe-dir] ok")
        sys.exit(0)
print("[patch-git-safe-dir] runGitShort already patched or anchor not found", file=sys.stderr)
sys.exit(0)
PY
