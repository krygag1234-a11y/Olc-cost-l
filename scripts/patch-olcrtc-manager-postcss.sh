#!/usr/bin/env bash
# Node 20 without "type":"module" cannot load ESM postcss.config.js — use CJS for vite build.
set -euo pipefail
MGR_REPO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}}"
PCSS="$MGR_REPO/postcss.config.js"
[[ -f "$PCSS" ]] || exit 0
if grep -q 'module.exports' "$PCSS"; then
  echo "[patch-manager-postcss] already cjs"
  exit 0
fi
cat >"$PCSS" <<'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF
echo "[patch-manager-postcss] ok"
