#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-}"
[[ -n "$ROOT" && -d "$ROOT" ]] || { echo "usage: $0 <vendored-manager-dir>" >&2; exit 2; }

required=(
  "$ROOT/go.mod"
  "$ROOT/go.sum"
  "$ROOT/package.json"
  "$ROOT/package-lock.json"
  "$ROOT/src/main.tsx"
  "$ROOT/cmd/olcrtc-manager/main.go"
  "$ROOT/cmd/olcrtc-manager/web/dist/index.html"
  "$ROOT/.olc-ui-source-sha256"
)
for path in "${required[@]}"; do
  [[ -f "$path" ]] || { echo "vendored manager is incomplete: missing $path" >&2; exit 1; }
done

if [[ "${OLC_ALLOW_VENDORED_BUILD_STATE:-0}" != "1" ]]; then
  if find "$ROOT" -type d \( -name .git -o -name node_modules \) -print -quit | grep -q .; then
    echo "vendored manager contains forbidden .git or node_modules" >&2
    exit 1
  fi
fi
if find "$ROOT" -type f \( -name '*.orig' -o -name '*.rej' \) -print -quit | grep -q .; then
  echo "vendored manager contains patch leftovers" >&2
  exit 1
fi

actual="$({
  find "$ROOT/src" -type f -print0
  printf '%s\0' \
    "$ROOT/index.html" \
    "$ROOT/package.json" \
    "$ROOT/package-lock.json" \
    "$ROOT/postcss.config.js" \
    "$ROOT/tailwind.config.ts" \
    "$ROOT/tsconfig.json" \
    "$ROOT/vite.config.ts"
} | sed -z "s#${ROOT%/}/##g" | sort -z | while IFS= read -r -d '' rel; do
  sha256sum "$ROOT/$rel" | sed "s#  $ROOT/#  #"
done | sha256sum | awk '{print $1}')"
expected="$(tr -d '[:space:]' <"$ROOT/.olc-ui-source-sha256")"
[[ "$actual" == "$expected" ]] || {
  echo "vendored UI source hash mismatch: expected $expected, got $actual" >&2
  echo "rebuild UI and update .olc-ui-source-sha256 in the same commit" >&2
  exit 1
}

asset_ref="$(grep -o 'assets/index-[A-Za-z0-9_-]*\.js' "$ROOT/cmd/olcrtc-manager/web/dist/index.html" | head -n1 || true)"
[[ -n "$asset_ref" && -f "$ROOT/cmd/olcrtc-manager/web/dist/$asset_ref" ]] || {
  echo "vendored UI bundle referenced by index.html is missing" >&2
  exit 1
}

grep -q 'OLC_JITSI_BATCH_IMPORT_V1' "$ROOT/src/main.tsx" || {
  echo "vendored manager baseline marker is missing" >&2
  exit 1
}

echo "vendored manager verified: UI source $actual, bundle $asset_ref"
