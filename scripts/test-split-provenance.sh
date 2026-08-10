#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_TSX="$ROOT/components/olcrtc-manager/src/main.tsx"

out="$(bash "$ROOT/scripts/olc-split-analyze.sh" self-test-provenance)"
grep -q '"status": "ok"' <<<"$out"
grep -q '"certificate"' <<<"$out"
grep -q '"runtime_log"' <<<"$out"

grep -q 'const splitDomainWithProvenance' "$MAIN_TSX"
grep -q 'domainLines.join("\\n")' "$MAIN_TSX"

echo "[split-provenance-test] OK: analyzer metadata + vendored UI contract"
