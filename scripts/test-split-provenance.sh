#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/olc-split-provenance.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

out="$(bash "$ROOT/scripts/olc-split-analyze.sh" self-test-provenance)"
grep -q '"status": "ok"' <<<"$out"
grep -q '"certificate"' <<<"$out"
grep -q '"runtime_log"' <<<"$out"

cp "$ROOT/packaging/golden-panel/main.tsx" "$tmp/main.tsx"
bash "$ROOT/scripts/patch-olcrtc-manager-panel-split-provenance-ui.sh" "$tmp/main.tsx" >/dev/null
bash "$ROOT/scripts/patch-olcrtc-manager-panel-split-provenance-ui.sh" "$tmp/main.tsx" >/dev/null
grep -q 'const splitDomainWithProvenance' "$tmp/main.tsx"
grep -q 'domainLines.join("\\n")' "$tmp/main.tsx"

echo "[split-provenance-test] OK: analyzer metadata + idempotent UI patch"
