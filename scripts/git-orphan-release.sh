#!/usr/bin/env bash
# Rewrite history to a single root commit + optional release tag (run manually).
# WARNING: requires force-push and breaks clone URLs for anyone on old history.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-v0.9.0-alpha.2}"
MSG="${2:-Release $TAG — Olc-cost-l panel stack}"

cd "$REPO_ROOT"
[[ -d .git ]] || { echo "Not a git repo: $REPO_ROOT" >&2; exit 1; }

echo "This will create orphan branch release-root with ONE commit and tag $TAG"
echo "Old history stays in branch archive/pre-orphan-$(date +%Y%m%d)"
read -r -p "Type YES to continue: " ok
[[ "$ok" == "YES" ]] || exit 1

git branch "archive/pre-orphan-$(date +%Y%m%d)" 2>/dev/null || true
git checkout --orphan release-root
git add -A
git commit -m "$MSG"
git tag -f "$TAG"
echo "Done. To publish: git push origin release-root --force && git push origin $TAG --force"
echo "Then set default branch to release-root on GitHub if desired."
