#!/usr/bin/env bash
# Add auto-check toggle + unblock probe button.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-auto-check] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label):
    global t, changed
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-auto-check] {label}: ok")
    else:
        print(f"[patch-auto-check] WARN: {label} not found")

# 1. Add auto-check state vars
old_health = '''  const health = (settings.health as Record<string, unknown>[]) ?? [];'''
new_health = '''  const health = (settings.health as Record<string, unknown>[]) ?? [];
  const [autoCheckEnabled, setAutoCheckEnabled] = useState(Boolean(settings.auto_bridge_check));
  const [autoCheckInterval, setAutoCheckInterval] = useState(Number(settings.auto_bridge_check_interval ?? 300));'''

repl(old_health, new_health, "add auto-check state")

# 2. Unblock probe button
old_disabled = '''disabled={probeBusy || jobStatus === "running"}'''
new_disabled = '''disabled={probeBusy}'''

repl(old_disabled, new_disabled, "unblock probe button")

# 3. Add auto-check checkbox next to button
old_btn = '''{probeBusy ? "Проверяю…" : "Проверить сейчас"}'''
new_btn = '''{probeBusy ? "Проверяю…" : "Проверить сейчас"}
              <label className="flex items-center gap-1.5 text-[10px] text-muted-foreground ml-2">
                <input type="checkbox" checked={autoCheckEnabled} onChange={(e) => setAutoCheckEnabled(e.target.checked)} />
                Автопроверка
              </label>'''

repl(old_btn, new_btn, "add auto-check checkbox")

if changed:
    f.write_text(t)
print("[patch-auto-check] ok")
PY
