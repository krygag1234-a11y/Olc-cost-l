#!/usr/bin/env bash
# Merge upstream-pins.json + mirror refs into version.json "stack" (release manifest).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
VERSION_FILE="${VERSION_FILE:-$REPO_ROOT/version.json}"
PINS="${UPSTREAM_PINS:-$REPO_ROOT/data/upstream-pins.json}"

[[ -f "$VERSION_FILE" ]] || { echo "missing $VERSION_FILE" >&2; exit 1; }
[[ -f "$PINS" ]] || { echo "missing $PINS" >&2; exit 1; }

sha="$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo "")"

jq \
  --slurpfile pins "$PINS" \
  --arg sha "$sha" \
  --arg mirror "${WEBTUNNEL_MIRROR_URL:-https://github.com/krygag1234-a11y/mirror-cry/releases/latest/download}" \
  '
  .stack = {
    "olc-cost-l": { repo: .repo, sha: $sha },
    olcrtc: ($pins[0].olcrtc | {repo, branch, ref: .pinned_sha}),
    "olcrtc-manager": ($pins[0]["olcrtc-manager"] | {repo, branch, ref: .pinned_sha}),
    zapret4rocket: ($pins[0].zapret4rocket | {repo, branch, ref: .pinned_sha}),
    "webtunnel-client": {
      source: "mirror-cry",
      repo: "https://github.com/krygag1234-a11y/mirror-cry",
      download: $mirror,
      note: "prebuilt binary; NOT gitlab.torproject.org"
    },
    olcbox: {
      source: "alananisimov/olcbox",
      channel: "nightly",
      url: "https://github.com/alananisimov/olcbox/releases/tag/nightly"
    }
  }
  | .release = (.release // {}) + { tag: ("v" + (.panel | ltrimstr("v"))), olc_cost_l_sha: $sha }
  ' "$VERSION_FILE" >"${VERSION_FILE}.tmp"
mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
echo "[version-stack] ok $(jq -r '.panel' "$VERSION_FILE")"
