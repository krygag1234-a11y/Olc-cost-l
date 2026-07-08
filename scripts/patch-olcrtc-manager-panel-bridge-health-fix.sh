#!/usr/bin/env bash
# Phase 1: Fix bridge health UI - unblock check button, add auto-check, dead bridge delete, progress bar.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-bridge-health-fix] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-bridge-health-fix] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-bridge-health-fix] {label}: ok")
    else:
        print(f"[patch-bridge-health-fix] WARN {label}: anchor not found")

# --- 1. Add auto-check interval state + toggle ---
repl(
    '  const health = (settings.health as Record<string, unknown>[]) ?? [];',
    '''  const health = (settings.health as Record<string, unknown>[]) ?? [];
  // --- Auto health check ---
  const [autoCheckEnabled, setAutoCheckEnabled] = useState(Boolean(settings.auto_bridge_check));
  const [autoCheckInterval, setAutoCheckInterval] = useState(Number(settings.auto_bridge_check_interval ?? 300));
  const [autoCheckNext, setAutoCheckNext] = useState<number | null>(null);
  // Auto-check timer
  useEffect(() => {
    if (!autoCheckEnabled) { setAutoCheckNext(null); return; }
    const runCheck = async () => {
      setProbeBusy(true);
      try {
        const res = await fetch("/api/settings/bridges", {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "probe_now" }),
        });
        const body = await res.json() as { pool_job?: Record<string, unknown>; error?: string };
        if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
        setSettings((s) => ({ ...s, pool_job: body.pool_job ?? { status: "running" } }));
        // Wait for completion
        const started = Date.now();
        while (Date.now() - started < 480_000) {
          await new Promise((r) => window.setTimeout(r, 1500));
          const res2 = await fetch("/api/settings/bridges", { cache: "no-store" });
          if (!res2.ok) break;
          const raw2 = await res2.text();
          let b2: { settings?: Record<string, unknown> } = {};
          try { b2 = (raw2 ? JSON.parse(raw2) : {}) as { settings?: Record<string, unknown> }; } catch { break; }
          setSettings((s) => ({ ...s, ...(b2.settings ?? {}) }));
          const st = String((b2.settings?.pool_job as Record<string, unknown>)?.status ?? "");
          if (st === "done" || st === "error") break;
        }
      } catch { /* ignore */ } finally { setProbeBusy(false); }
    };
    // Initial run after delay
    setAutoCheckNext(Date.now() + autoCheckInterval * 1000);
    const timer = setInterval(() => {
      runCheck();
      setAutoCheckNext(Date.now() + autoCheckInterval * 1000);
    }, autoCheckInterval * 1000);
    return () => clearInterval(timer);
  }, [autoCheckEnabled, autoCheckInterval]);''',
    "auto-check state + timer",
    guard='useEffect(() => {',
)

# --- 2. Unblock "Проверить сейчас" button (remove disabled check) ---
repl(
    'disabled={probeBusy || jobStatus === "running"}',
    'disabled={probeBusy}',
    "unblock check button",
    "unblock check button",
)

# --- 3. Add auto-check settings in health section ---
old_health_btn = '''            <button
              type="button"
              className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
              disabled={probeBusy}
              onClick={() => void probeNow()}
            >
              {probeBusy ? "Проверяю…" : "Проверить сейчас"}
            </button>'''

new_health_btn = '''            <div className="flex items-center gap-2">
              <button
                type="button"
                className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
                disabled={probeBusy}
                onClick={() => void probeNow()}
              >
                {probeBusy ? "Проверяю…" : "Проверить сейчас"}
              </button>
              <label className="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                <input
                  type="checkbox"
                  className="rounded border-border"
                  checked={autoCheckEnabled}
                  onChange={(e) => {
                    setAutoCheckEnabled(e.target.checked);
                    setSettings((s) => ({ ...s, auto_bridge_check: e.target.checked ? 1 : 0 }));
                  }}
                />
                Автопроверка
              </label>
              {autoCheckEnabled && (
                <div className="flex items-center gap-1">
                  <input
                    type="number"
                    className="h-6 w-12 rounded border border-border bg-background px-1 text-[10px] text-right"
                    min="30"
                    max="3600"
                    step="30"
                    value={Math.max(30, Math.min(3600, autoCheckInterval))}
                    onChange={(e) => {
                      const val = Math.max(30, Math.min(3600, Number(e.target.value)));
                      setAutoCheckInterval(val);
                      setSettings((s) => ({ ...s, auto_bridge_check_interval: val }));
                    }}
                  />
                  <span className="text-[10px] text-muted-foreground">сек</span>
                </div>
              )}
            </div>'''

repl(old_health_btn, new_health_btn, "auto-check settings in health", "auto-check settings in health")

# --- 4. Add delete button for dead bridges ---
old_health_list = '''            {health.map((h, i) => {
              const alive = Boolean(h.alive);
              const checked = Boolean(h.checked);
              const ts = Number(h.checked_at ?? 0);
              const when = ts > 0 ? new Date(ts * 1000).toLocaleString() : "—";
              return (
                <div key={i} className="flex items-center gap-2 rounded bg-background/60 px-2 py-1 font-mono">
                  <span
                    className={`inline-block h-2 w-2 shrink-0 rounded-full ${!checked ? "bg-muted-foreground" : alive ? "bg-emerald-400" : "bg-destructive"}`}
                    title={!checked ? "не проверялся" : alive ? "жив" : "мёртв"}
                  />
                  <span className="w-20 shrink-0 text-muted-foreground">{String(h.type ?? "?")}</span>
                  <span className="flex-1 truncate">{String(h.addr ?? "")}</span>
                  <span className="shrink-0 text-[10px] text-muted-foreground" title={String(h.last_status ?? "")}>{checked ? when : "не проверен"}</span>
                </div>
              );
            })}'''

new_health_list = '''            {health.map((h, i) => {
              const alive = Boolean(h.alive);
              const checked = Boolean(h.checked);
              const ts = Number(h.checked_at ?? 0);
              const when = ts > 0 ? new Date(ts * 1000).toLocaleString() : "—";
              return (
                <div key={i} className="flex items-center gap-2 rounded bg-background/60 px-2 py-1 font-mono">
                  <span
                    className={`inline-block h-2 w-2 shrink-0 rounded-full ${!checked ? "bg-muted-foreground" : alive ? "bg-emerald-400" : "bg-destructive"}`}
                    title={!checked ? "не проверялся" : alive ? "жив" : "мёртв"}
                  />
                  <span className="w-20 shrink-0 text-muted-foreground">{String(h.type ?? "?")}</span>
                  <span className="flex-1 truncate" title={String(h.addr ?? "")}>{String(h.addr ?? "")}</span>
                  <span className="shrink-0 text-[10px] text-muted-foreground" title={String(h.last_status ?? "")}>{checked ? when : "не проверен"}</span>
                  {alive === false && checked && (
                    <button
                      type="button"
                      className="text-destructive text-[10px] hover:underline hover:text-destructive/80"
                      onClick={async () => {
                        if (!window.confirm(`Удалить мёртвый мост?\\n${h.addr}\\n${h.type}`)) return;
                        try {
                          const res = await fetch("/api/settings/bridges", {
                            method: "PUT",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ action: "remove_dead", addr: h.addr }),
                          });
                          const body = await res.json() as { error?: string };
                          if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
                          await loadHealth();
                        } catch (e) {
                          setPoolHint(e instanceof Error ? e.message : "Ошибка удаления");
                        }
                      }}
                    >
                      ✕
                    </button>
                  )}
                </div>
              );
            })}'''

repl(old_health_list, new_health_list, "add delete button for dead", "add delete button for dead")

# --- 5. Add loadHealth helper + progress bar state ---
repl(
    '  const probeNow = async () => {',
    '''  const loadHealth = async () => {
    try {
      const res = await fetch("/api/settings/bridges", { cache: "no-store" });
      if (res.ok) {
        const text = await res.text();
        const body = JSON.parse(text) as { settings?: Record<string, unknown> };
        if (body.settings) setSettings((s) => ({ ...s, ...body.settings }));
      }
    } catch { /* ignore */ }
  };
  
  // Progress bar state
  const totalBridges = settings.pool_stats?.total ?? 0;
  const fetchedBridges = settings.pool_stats?.fetched ?? 0;
  const progressBarWidth = totalBridges > 0 ? Math.round((fetchedBridges / totalBridges) * 100) : 0;
  const isProcessing = jobStatus === "running" && poolHint.includes("обновлени") && progressBarWidth > 0;
  
  const probeNow = async () => {''',
    "progress bar state + loadHealth",
    "progress bar state + loadHealth",
)

# --- 6. Add progress bar in health section ---
old_health_span = '''        <div className="flex flex-wrap items-center justify-between gap-2">'''
new_health_span = '''        <div className="flex flex-wrap items-center justify-between gap-2">
          {/* Progress bar */}
          {isProcessing && (
            <div className="w-full">
              <div className="mb-1 flex items-center justify-between text-[10px] text-muted-foreground">
                <span>{poolHint}</span>
                <span>{progressBarWidth}%</span>
              </div>
              <div className="h-2 w-full rounded-full border border-border bg-muted">
                <div
                  className="h-2 rounded-full bg-primary transition-all duration-500"
                  style={{ width: `${progressBarWidth}%` }}
                />
              </div>
            </div>
          )}'''

repl(old_health_span, new_health_span, "progress bar", "progress bar")

if changed:
    f.write_text(t)
print("[patch-bridge-health-fix] ok")
PY
