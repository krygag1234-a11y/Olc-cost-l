#!/usr/bin/env bash
# Fix: wrap probe button + auto-check in div (label inside button is invalid JSX).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-auto-check-fix] ERROR: $MAIN_TSX not found"; exit 1; }

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
        print(f"[patch-auto-check-fix] {label}: ok")
    else:
        print(f"[patch-auto-check-fix] WARN: {label} not found")

# Current broken code (label inside button)
old = '''<button
              type="button"
              className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
              disabled={probeBusy}
              onClick={() => void probeNow()}
            >
              {probeBusy ? "Проверяю…" : "Проверить сейчас"}
              <label className="flex items-center gap-1.5 text-[10px] text-muted-foreground ml-2">
                <input type="checkbox" checked={autoCheckEnabled} onChange={(e) => setAutoCheckEnabled(e.target.checked)} />
                Автопроверка
              </label>'''

new = '''<div className="flex items-center gap-2">
              <button
                type="button"
                className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
                disabled={probeBusy}
                onClick={() => void probeNow()}
              >
                {probeBusy ? "Проверяю…" : "Проверить сейчас"}
              </button>
              <label className="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                <input type="checkbox" checked={autoCheckEnabled} onChange={(e) => setAutoCheckEnabled(e.target.checked)} />
                Автопроверка
              </label>
            </div>'''

repl(old, new, "wrap button+label in div")

if changed:
    f.write_text(t)
print("[patch-auto-check-fix] ok")
PY
