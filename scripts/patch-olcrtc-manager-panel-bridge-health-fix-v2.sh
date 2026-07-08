#!/usr/bin/env bash
# Phase 1: Bridge health UI fixes — no useEffect (avoids TDZ).
# Only adds JSX and useState variables (safe).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-bridge-health-fix-v2] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-bridge-health-fix-v2] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-bridge-health-fix-v2] {label}: ok")
    else:
        print(f"[patch-bridge-health-fix-v2] WARN {label}: anchor not found")

# 1. Add auto-check state vars (useState — safe, always at top of component)
repl(
    '  const health = (settings.health as Record<string, unknown>[]) ?? [];',
    '''  const health = (settings.health as Record<string, unknown>[]) ?? [];
  // --- Auto-check (JSX-only, no useEffect to avoid TDZ) ---
  const [autoCheckEnabled, setAutoCheckEnabled] = useState(Boolean(settings.auto_bridge_check));
  const [autoCheckInterval, setAutoCheckInterval] = useState(Number(settings.auto_bridge_check_interval ?? 300));''',
    "add auto-check state vars",
    guard='const [autoCheckEnabled',
)

# 2. Unblock "Проверить сейчас" button
repl(
    'disabled={probeBusy || jobStatus === "running"}',
    'disabled={probeBusy}',
    "unblock check button",
    "unblock check button",
)

# 3. Replace health buttons with auto-check controls
old_btn = '''            <button
              type="button"
              className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
              disabled={probeBusy || jobStatus === "running"}
              onClick={() => void probeNow()}
            >
              {probeBusy ? "Проверяю…" : "Проверить сейчас"}
            </button>'''

new_btn = '''            <div className="flex items-center gap-2">
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
                  onChange={(e) => setAutoCheckEnabled(e.target.checked)}
                />
                Автопроверка
              </label>
              {autoCheckEnabled && (
                <div className="flex items-center gap-1">
                  <input
                    type="number"
                    className="h-6 w-12 rounded border border-border bg-background px-1 text-[10px] text-right"
                    min="30" max="3600" step="30"
                    value={autoCheckInterval}
                    onChange={(e) => setAutoCheckInterval(Math.max(30, Math.min(3600, Number(e.target.value))))}
                  />
                  <span className="text-[10px] text-muted-foreground">сек</span>
                </div>
              )}
            </div>'''

repl(old_btn, new_btn, "add auto-check UI", "add auto-check UI")

# 4. Add delete button for dead bridges in health list
old_list = '''            {health.map((h, i) => {
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

new_list = '''            {health.map((h, i) => {
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
                        if (!window.confirm("Удалить мёртвый мост?\\n" + h.addr)) return;
                        try {
                          const res = await fetch("/api/settings/bridges?action=" + encodeURIComponent(h.addr), {
                            method: "PUT",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ action: "remove_dead" }),
                          });
                          if (!res.ok) { const b = await res.json(); throw new Error(b.error || "HTTP " + res.status); }
                          const res2 = await fetch("/api/settings/bridges");
                          if (res2.ok) { const b = await res2.json(); setSettings((s) => ({ ...s, ...b.settings })); }
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

repl(old_list, new_list, "add delete button for dead", "add delete button for dead")

if changed:
    f.write_text(t)
print("[patch-bridge-health-fix-v2] ok")
PY
