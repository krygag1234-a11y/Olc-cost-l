#!/usr/bin/env bash
# Fix useCallback import for UpdateAvailableToast (roadmap-finish-v1).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-roadmap-finish-v2' "$MAIN_TSX" && { echo "[patch-panel-roadmap-finish-v2] already applied"; exit 0; }
grep -q 'UpdateAvailableToast' "$MAIN_TSX" || { echo "[patch-panel-roadmap-finish-v2] skip (no toast)"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()

if '/* olc-roadmap-finish-v2 */' not in t:
    t = t.replace('/* olc-roadmap-finish-v1 */', '/* olc-roadmap-finish-v1 */\n/* olc-roadmap-finish-v2 */', 1)

old_imp = 'import React, { useEffect, useState } from "react";'
new_imp = 'import React, { useCallback, useEffect, useState } from "react";'
if old_imp in t and 'useCallback' not in t.split('from "react"')[0]:
    t = t.replace(old_imp, new_imp, 1)

# Fallback: remove useCallback from toast if import patch missed stacked imports
if 'useCallback is not defined' in t or ('useCallback(async' in t and 'useCallback' not in t[:500]):
    pass

if 'function UpdateAvailableToast' in t and 'useCallback(async' in t:
    old_toast = '''  const check = useCallback(async () => {
    try {
      const res = await fetch("/api/updates/check", { cache: "no-store" });
      if (!res.ok) return;
      const b = (await res.json()) as { available?: boolean };
      if (b.available && !dismissed) setShow(true);
    } catch { /* ignore */ }
  }, [dismissed]);
  useEffect(() => {
    void check();
    const id = window.setInterval(() => void check(), 6 * 60 * 60 * 1000);
    return () => window.clearInterval(id);
  }, [check]);'''
    new_toast = '''  useEffect(() => {
    const check = async () => {
      try {
        const res = await fetch("/api/updates/check", { cache: "no-store" });
        if (!res.ok) return;
        const b = (await res.json()) as { available?: boolean };
        if (b.available && !dismissed) setShow(true);
      } catch { /* ignore */ }
    };
    void check();
    const id = window.setInterval(() => void check(), 6 * 60 * 60 * 1000);
    return () => window.clearInterval(id);
  }, [dismissed]);'''
    if old_toast in t:
        t = t.replace(old_toast, new_toast, 1)

p.write_text(t)
print("[patch-panel-roadmap-finish-v2] ok"); raise SystemExit(0)
PY
