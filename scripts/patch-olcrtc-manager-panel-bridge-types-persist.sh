#!/usr/bin/env bash
# Fix: persist bridge types selection when clicking "Обновить сейчас" without explicit Save.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-bridge-types-persist-fix' "$MAIN_TSX" && { echo "[patch-bridge-types-persist] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Add marker
if 'olc-bridge-types-persist-fix' not in t:
    t = t.replace('function BridgesSettingsFields', '/* olc-bridge-types-persist-fix */\nfunction BridgesSettingsFields', 1)

# Replace refreshPool function to save types first
old_refresh = '''  const refreshPool = async (types: string) => {
    const res = await fetch("/api/settings/bridges", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "refresh_pool", types }),
    });
    setMsg(res.ok ? "Обновление пула запущено" : `HTTP ${res.status}`);
  };'''

new_refresh = '''  const refreshPool = async (types: string) => {
    // Save current types first
    const saveRes = await fetch("/api/settings/bridges", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ profiles: { ...prof, system: { ...sys, types } } }),
    });
    if (!saveRes.ok) {
      setMsg(`Ошибка сохранения типов: HTTP ${saveRes.status}`);
      return;
    }
    // Then refresh pool
    const res = await fetch("/api/settings/bridges", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "refresh_pool", types }),
    });
    setMsg(res.ok ? "Обновление пула запущено" : `HTTP ${res.status}`);
  };'''

if old_refresh in t:
    t = t.replace(old_refresh, new_refresh, 1)

p.write_text(t)
print("[patch-bridge-types-persist] ok")
PY
