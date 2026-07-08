#!/usr/bin/env bash
# Small UX polish: remove the log-source path label(s) from the addon log modal
# (FeatureLogsModal showed it twice: "/var/log/olcrtc-..."). Modal-open memory is
# handled generically by patch-olcrtc-manager-panel-modal-memory.sh.
# Idempotent. Target: manager src/main.tsx. Run late (after autologi-ui).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-logs-polish] ERROR: $MAIN_TSX not found"; exit 1; }

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
        print(f"[patch-logs-polish] {label}: ok")
    else:
        print(f"[patch-logs-polish] {label}: anchor not found (ok if already applied)")

# Remove path in the header row of FeatureLogsModal
repl(
    '          {path && <div className="text-xs text-muted-foreground truncate">{path}</div>}\n',
    '',
    "remove header path label",
)
# Remove the second path line above the log box
repl(
    '        {path && <div className="mb-2 text-xs text-muted-foreground">{path}</div>}\n',
    '',
    "remove second path label",
)

if changed:
    f.write_text(t)
print("[patch-logs-polish] ok")
PY
