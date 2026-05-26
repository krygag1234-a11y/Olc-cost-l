#!/usr/bin/env bash
# Create GitHub Release from version.json (tag v{panel} on current main).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
VERSION_FILE="${VERSION_FILE:-$REPO_ROOT/version.json}"

[[ -f "$VERSION_FILE" ]] || { echo "missing $VERSION_FILE" >&2; exit 1; }

PANEL_VER="$(jq -r '.panel // empty' "$VERSION_FILE")"
REPO_SLUG="$(jq -r '.repo // "https://github.com/krygag1234-a11y/Olc-cost-l"' "$VERSION_FILE" | sed -E 's#^https?://github.com/##; s#/$##')"
TAG="v${PANEL_VER#v}"
CHANNEL="$(jq -r '.channel // "alpha"' "$VERSION_FILE")"
DESC="$(jq -r '.description // "Olc-cost-l release"' "$VERSION_FILE")"

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "Set GITHUB_TOKEN or GH_TOKEN to create a release." >&2
  exit 1
fi

BODY="$(cat <<EOF
## Olc-cost-l ${PANEL_VER}

${DESC}

- Канал: **${CHANNEL}**
- Установка: \`curl -fsSL https://raw.githubusercontent.com/${REPO_SLUG}/main/install.sh | sudo bash -s --\`
- Обновление с панели: «Обновить с GitHub» или \`sudo olc-update\`

### version.json
\`\`\`json
$(cat "$VERSION_FILE")
\`\`\`
EOF
)"

payload="$(jq -n \
  --arg tag "$TAG" \
  --arg name "$PANEL_VER" \
  --arg body "$BODY" \
  '{tag_name:$tag,name:$name,body:$body,target_commitish:"main",draft:false,prerelease:true}')"

echo "Creating release $TAG on $REPO_SLUG ..."
resp="$(curl -sS -w "\n%{http_code}" -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO_SLUG}/releases" \
  -d "$payload")"
code="${resp##*$'\n'}"
body="${resp%$'\n'*}"
if [[ "$code" != "201" ]]; then
  echo "GitHub API error HTTP $code:" >&2
  echo "$body" >&2
  exit 1
fi
upload_url="$(echo "$body" | jq -r '.upload_url' | sed 's/{?name,label}//')"
if [[ -n "$upload_url" && "$upload_url" != "null" ]]; then
  curl -sS -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    "${upload_url}?name=version.json" \
    --data-binary @"$VERSION_FILE" >/dev/null
  echo "Attached version.json"
fi
echo "Release created: https://github.com/${REPO_SLUG}/releases/tag/${TAG}"
