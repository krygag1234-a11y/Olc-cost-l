#!/usr/bin/env bash
# Push current branch to origin using GITHUB_TOKEN from .env
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-github-token.sh
source "$SCRIPT_DIR/lib-github-token.sh"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BRANCH="${1:-main}"
cd "$REPO_ROOT"
url="$(olc_git_push_url)"
GIT_TERMINAL_PROMPT=0 git push "$url" "$BRANCH"
