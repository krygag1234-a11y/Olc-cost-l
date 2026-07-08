#!/usr/bin/env bash
# B5: fix "hanging" feature toggle buttons + block bridges when Tor is off.
#
# Hanging buttons — real root cause:
#   A toggle POST /api/features/<name> returns 200 with the new {flags} in ~5s,
#   but ~2s later the manager RESTARTS and is unreachable for ~8-10s. The old
#   toggle() did `await load()` (a plain GET) BEFORE clearing busy, so busy stayed
#   set for the whole restart window and the button froze at "…".
#   Fix: apply the flags returned by the POST directly and clear busy immediately;
#   do NOT block on a follow-up GET. A background refresh (resilient, retried) then
#   reconciles once the manager is back.
#
# Bridges-require-Tor:
#   Backend already rejects enabling webtunnel without Tor. Mirror it in the UI:
#   - postFeatureToggle throws a clear RU message.
#   - FeaturesPanel enable button is disabled when Tor is off (header already had it).
#
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

# --- 1. Resilient background fetch helper (used to reconcile after restart) ---
repl(
    'async function postFeatureToggle(name: FeatureName, enabled: boolean, flags?: Record<FeatureName, boolean>) {',
    '''async function featuresFetch(): Promise<Response> {
  // The manager restarts ~2s after a toggle and is unreachable ~8-10s. Try a few
  // times with per-attempt timeouts so a background refresh eventually succeeds.
  const attempt = async (timeoutMs: number): Promise<Response> => {
    const ctrl = new AbortController();
    const timer = window.setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      return await fetch("/api/features", { cache: "no-store", signal: ctrl.signal });
    } finally {
      window.clearTimeout(timer);
    }
  };
  let lastErr: unknown;
  for (let i = 0; i < 8; i++) {
    try {
      const res = await attempt(4000);
      if (res.ok) return res;
      lastErr = new Error(`HTTP ${res.status}`);
    } catch (e) {
      lastErr = e;
    }
    await new Promise((r) => window.setTimeout(r, 2000));
  }
  throw lastErr ?? new Error("features unavailable");
}

async function postFeatureToggle(name: FeatureName, enabled: boolean, flags?: Record<FeatureName, boolean>) {''',
    "featuresFetch helper",
    guard='async function featuresFetch(',
)

# --- 2. Add bridges(webtunnel)-require-Tor guard in postFeatureToggle ---
repl(
    '''  if (name === "split" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — split маршрутизирует остальной трафик через exit");
  }''',
    '''  if (name === "split" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — split маршрутизирует остальной трафик через exit");
  }
  if (name === "webtunnel" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — мосты (obfs4/webtunnel) работают только поверх Tor");
  }''',
    "bridges-require-tor guard",
    guard='мосты (obfs4/webtunnel) работают только поверх Tor',
)

# --- 3. HeaderNetworkToggles.toggle: apply POST flags, clear busy immediately ---
repl(
    '''  const toggle = async (name: FeatureName) => {
    if (!flags) return;
    setBusy(name);
    setErr("");
    try {
      const enabled = !flags[name];
      await postFeatureToggle(name, enabled, flags);
      await load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };''',
    '''  const toggle = async (name: FeatureName) => {
    if (!flags) return;
    setBusy(name);
    setErr("");
    try {
      const enabled = !flags[name];
      const body = await postFeatureToggle(name, enabled, flags);
      // The POST already returns the new flags; apply them and release the button
      // right away instead of blocking on a GET during the manager restart window.
      if (body && body.flags) setFlags(body.flags as Record<FeatureName, boolean>);
      setBusy(null);
      // Reconcile in the background once the manager is back (non-blocking).
      void featuresFetch()
        .then((res) => res.json())
        .then((b) => { if (b && b.flags) setFlags(b.flags as Record<FeatureName, boolean>); })
        .catch(() => {});
      return;
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };''',
    "HeaderNetworkToggles.toggle non-blocking",
    guard='apply them and release the button',
)

# --- 4. FeaturesPanel.toggle: same non-blocking pattern ---
repl(
    '''  const toggle = async (name: FeatureName, enabled: boolean) => {
    setBusy(name);
    setErr("");
    try {
      await postFeatureToggle(name, enabled, data?.flags);
      await load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };''',
    '''  const toggle = async (name: FeatureName, enabled: boolean) => {
    setBusy(name);
    setErr("");
    try {
      const body = await postFeatureToggle(name, enabled, data?.flags);
      // Apply flags from the POST response and release the button immediately;
      // don't block on a GET while the manager is restarting.
      if (body && body.flags) setData((prev: any) => ({ ...(prev ?? {}), flags: body.flags }));
      setBusy(null);
      void featuresFetch()
        .then((res) => res.json())
        .then((b) => { if (b) setData(b); })
        .catch(() => {});
      return;
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };''',
    "FeaturesPanel.toggle non-blocking",
    guard="don't block on a GET while the manager is restarting",
)

# --- 5. FeaturesPanel enable button: disable bridges(webtunnel) when Tor off ---
repl(
    '''                      busy !== null ||
                      (row.name === "split" && !enabled && !data.flags?.tor) ||''',
    '''                      busy !== null ||
                      (row.name === "split" && !enabled && !data.flags?.tor) ||
                      (row.name === "webtunnel" && !enabled && !data.flags?.tor) ||''',
    "FeaturesPanel bridges disabled when tor off",
    guard='(row.name === "webtunnel" && !enabled && !data.flags?.tor) ||',
)

if changed:
    f.write_text(t)
print("[patch-toggle-resilient] ok")
PY
