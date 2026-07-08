#!/usr/bin/env bash
# Fix: remove extra </button> and </div> that broke the JSX structure.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-fix-extraneous] ERROR: $MAIN_TSX not found"; exit 1; }

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
        print(f"[patch-fix-extraneous] {label}: ok")
    else:
        print(f"[patch-fix-extraneous] WARN: {label} not found")

# Remove extra </button> and extra </div> after label
old = '''              <label className="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                <input type="checkbox" checked={autoCheckEnabled} onChange={(e) => setAutoCheckEnabled(e.target.checked)} />
                Автопроверка
              </label>
            </div>
            </button>
          </div>'''

new = '''              <label className="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                <input type="checkbox" checked={autoCheckEnabled} onChange={(e) => setAutoCheckEnabled(e.target.checked)} />
                Автопроверка
              </label>
            </div>
          </div>'''

repl(old, new, "remove extraneous </button> and </div>")

if changed:
    f.write_text(t)
print("[patch-fix-extraneous] ok")
PY
