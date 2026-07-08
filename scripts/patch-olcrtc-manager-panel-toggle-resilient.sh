#!/usr/bin/env bash
# B5: fix "hanging" feature toggle buttons (Zapret/Tor/Split/Мосты).
# Root cause: toggling a feature triggers a DEFERRED manager restart (~2s later,
# see _defer_manager_restart in olc-feature.sh). The follow-up load() does
# fetch("/api/features") with NO timeout, so if it lands while the manager is
# restarting the request hangs forever and the button stays stuck at "…".
# Fix: a resilient featuresFetch() with an AbortController timeout + one retry
# after a short delay (to ride out the restart), so busy state always clears.
# Idempotent. Target: manager src/main.tsx. Run last.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-toggle-resilient] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None, count=1):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-toggle-resilient] {label}: already applied")
        return
    n = t.count(old)
    if n >= count and n > 0:
        t = t.replace(old, new, count)
        changed = True
        print(f"[patch-toggle-resilient] {label}: ok ({count} of {n})")
    else:
        print(f"[patch-toggle-resilient] WARN {label}: anchor not found (have {n})")

# --- 1. Insert the resilient fetch helper right before postFeatureToggle ---
repl(
    'async function postFeatureToggle(name: FeatureName, enabled: boolean, flags?: Record<FeatureName, boolean>) {',
    '''async function featuresFetch(): Promise<Response> {
  // The manager restarts ~2s after a toggle; a plain fetch can hang or fail
  // during that window. Try with a timeout, then retry once after a short delay.
  const attempt = async (timeoutMs: number): Promise<Response> => {
    const ctrl = new AbortController();
    const timer = window.setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      return await fetch("/api/features", { cache: "no-store", signal: ctrl.signal });
    } finally {
      window.clearTimeout(timer);
    }
  };
  try {
    return await attempt(5000);
  } catch {
    await new Promise((r) => window.setTimeout(r, 3000));
    return attempt(8000);
  }
}

async function postFeatureToggle(name: FeatureName, enabled: boolean, flags?: Record<FeatureName, boolean>) {''',
    "featuresFetch helper",
    guard='async function featuresFetch(',
)

# --- 2. Swap both load() fetches to the resilient helper (identical lines) ---
repl(
    '      const res = await fetch("/api/features", { cache: "no-store" });',
    '      const res = await featuresFetch();',
    "swap load() fetches",
    guard='const res = await featuresFetch();',
    count=2,
)

if changed:
    f.write_text(t)
print("[patch-toggle-resilient] ok")
PY
