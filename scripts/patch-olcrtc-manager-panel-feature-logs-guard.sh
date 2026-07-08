#!/usr/bin/env bash
# Batch 1 frontend: disable the "Логи" button for a network-bypass addon when it
# is OFF (its logs aren't meaningful / cause the "not found" message). Keeps the
# olcrtc-core log button always enabled (core is always running).
# Idempotent. Target: manager src/main.tsx. Run after golden-panel copy.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-feature-logs-guard] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# Disable the addon log button when the feature is OFF.
btn_old = '''                  <button
                    type="button"
                    title="Логи"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted"
                    onClick={() => setLogFeature(row.name)}
                  >
                    <Terminal className="h-4 w-4" />
                  </button>'''
btn_new = '''                  <button
                    type="button"
                    title={enabled ? "Логи" : "Логи недоступны — дополнение выключено"}
                    disabled={!enabled}
                    className={`inline-flex h-8 w-8 items-center justify-center rounded-md border border-border ${enabled ? "hover:bg-muted" : "opacity-40 cursor-not-allowed"}`}
                    onClick={() => { if (enabled) setLogFeature(row.name); }}
                  >
                    <Terminal className="h-4 w-4" />
                  </button>'''
if 'title={enabled ? "Логи" : "Логи недоступны — дополнение выключено"}' in t:
    print("[patch-feature-logs-guard] log button already guarded")
elif btn_old in t:
    t = t.replace(btn_old, btn_new, 1)
    changed = True
    print("[patch-feature-logs-guard] addon log button disabled when OFF")
else:
    print("[patch-feature-logs-guard] WARN: log button anchor not found")

if changed:
    f.write_text(t)
print("[patch-feature-logs-guard] ok")
PY
