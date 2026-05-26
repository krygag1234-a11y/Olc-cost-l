#!/usr/bin/env bash
# Fix panelJobsHandler route registration (HandlerFunc vs Handler).
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
if grep -q 'adminAuth(panelJobsHandler())' "$MAIN_GO"; then
  echo "[patch-backend-v4-fix] already ok"
  exit 0
fi
sed -i 's|adminAuth(http.HandlerFunc(panelJobsHandler))|adminAuth(panelJobsHandler())|' "$MAIN_GO"
echo "[patch-backend-v4-fix] ok"
