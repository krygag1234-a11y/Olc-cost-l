#!/usr/bin/env bash
# Fix probe_now response parsing and progress bar display.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-probe-fix] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-probe-fix] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-probe-fix] {label}: ok")
    else:
        print(f"[patch-probe-fix] WARN {label}: anchor not found")

# Fix probeNow to handle response {pool_job, status} instead of {settings: {...}}
old_probe = '''xt = async () => {
      var T, $;
      Fe(!0), N(!0), E("Проверка мостов запущена…");
      try {
        const Q = await fetch("/api/settings/bridges", {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "probe_now" }),
        }), fe = await Q.json();
        if (!Q.ok) throw new Error(fe.error || `HTTP ${Q.status}`);
        t(Ue => ({ ...Ue, pool_job: fe.pool_job ?? { status: "running" } }));'''

new_probe = '''xt = async () => {
      var T, $;
      Fe(!0), N(!0), E("Проверка мостов запущена…");
      try {
        const Q = await fetch("/api/settings/bridges", {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "probe_now" }),
        }), fe = await Q.json();
        if (!Q.ok) throw new Error(fe.error || `HTTP ${Q.status}`);
        // Response is {pool_job: {...}, status: "ok"} not {settings: {...}}
        const pj = fe.pool_job || {};
        t(Ue => ({ ...Ue, pool_job: pj, status: fe.status || "ok" }));'''

repl(old_probe, new_probe, "fix probeNow response", "fix probeNow response")

# Fix progress bar display - show when probing
old_progress = '''  const isProcessing = jobStatus === "running" && poolHint.includes("обновлени") && progressBarWidth > 0;'''
new_progress = '''  const isProcessing = jobStatus === "running" && (poolHint.includes("обновлени") || poolHint.includes("Проверка") || poolHint.includes("проверя") || (typeof fe?.status === "string" && fe.status === "running"));'''
repl(old_progress, new_progress, "fix progress bar condition", "fix progress bar condition")

# Fix poolHint status display
old_status = '''{probeBusy ? "Проверяю…" : "Проверить сейчас"}'''
new_status = '''{probeBusy ? "Проверяю…" : "Проверить сейчас"}'''
# Already correct

if changed:
    f.write_text(t)
print("[patch-probe-fix] ok")
PY
