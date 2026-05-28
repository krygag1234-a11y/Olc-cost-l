#!/usr/bin/env bash
# Hotfix v24: i18n (ru/en), instance defaults, panel UI updates
set -euo pipefail
MGR_REPO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if grep -q 'olc-panel-hotfix-v24-lang' "$MGR_REPO/src/main.tsx" 2>/dev/null; then
    echo "[patch-panel-hotfix-v24-lang] already applied"
    exit 0
fi

patch -d "$MGR_REPO" -p0 < "$REPO_ROOT/patches/manager/v24-main-tsx-lang-defaults.patch" || { echo "Failed to apply main.tsx patch"; exit 1; }
patch -d "$MGR_REPO" -p0 < "$REPO_ROOT/patches/manager/v24-main-go-lang-defaults.patch" || { echo "Failed to apply main.go patch"; exit 1; }

echo "/* olc-panel-hotfix-v24-lang */" >> "$MGR_REPO/src/main.tsx"
echo "// olc-panel-hotfix-v24-lang" >> "$MGR_REPO/cmd/olcrtc-manager/main.go"

echo "[patch-panel-hotfix-v24-lang] ok"
