#!/usr/bin/env bash
# Phase 1 — bridge health UI in BridgesSettingsFields.
# Must run BEFORE bridge-sources-ui.
# Idempotent. Target: manager src/main.tsx.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-bridge-health-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-bridge-health-ui] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-bridge-health-ui] {label}: ok")
    else:
        print(f"[patch-bridge-health-ui] WARN {label}: anchor not found")

# --- 1. Health state + probe fn inside BridgesSettingsFields ---
repl(
    '  const [poolHint, setPoolHint] = useState("");',
    '''  const [poolHint, setPoolHint] = useState("");
  // --- Health check ---
  const health = (settings.health as Record<string, unknown>[]) ?? [];
  const aliveCount = health.filter((h) => Boolean(h.alive)).length;
  const unCheckedCount = health.filter((h) => !h.checked).length;
  const [healthOpen, setHealthOpen] = useState(false);
  const [probeBusy, setProbeBusy] = useState(false);
  const probeNow = async () => {
    setProbeBusy(true);
    setPoolUiOpen(true);
    setPoolHint("Проверка мостов запущена…");
    try {
      const res = await fetch("/api/settings/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "probe_now" }),
      });
      const body = (await res.json()) as { pool_job?: Record<string, unknown>; error?: string };
      if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
      setSettings((s) => ({ ...s, pool_job: body.pool_job ?? { status: "running" } }));
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
        if (st === "done") { setPoolHint("Проверка завершена"); break; }
        if (st === "error") { setPoolHint("Ошибка проверки"); break; }
        if (st !== "running") break;
      }
    } catch (e) {
      setPoolHint(e instanceof Error ? e.message : String(e));
    } finally {
      setProbeBusy(false);
    }
  };''',
    "health state + probeNow",
    guard='const probeNow = async () =>',
)

# --- 2. Render health block AFTER LogScrollPre for bridges_conf ---
# Use the CLOSE tag </> + func end as anchor.
# The original text (BEFORE any of our patches):
#   </LogScrollPre>
#   </>
#   );
# }
#
# function SettingsSection({
new_block = '''</LogScrollPre>
      {/* --- Health Check --- */}
      <div className="rounded-lg border border-border bg-muted/10 p-2.5 text-xs">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span>
            Здоровье мостов:{" "}
            <strong className="text-emerald-400">{aliveCount} живых</strong>
            {" · "}
            <strong className={unCheckedCount > 0 ? "text-muted-foreground" : "text-destructive"}>
              {unCheckedCount > 0 ? unCheckedCount + " не проверен" : (health.length - aliveCount) + " мёртвых"}
            </strong>
          </span>
          <div className="flex items-center gap-2">
            {health.length > 0 && (
              <button type="button" className="text-muted-foreground hover:text-foreground" onClick={() => setHealthOpen((v) => !v)}>
                {healthOpen ? "Скрыть" : "Показать список"}
              </button>
            )}
            <button
              type="button"
              className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
              disabled={probeBusy || jobStatus === "running"}
              onClick={() => void probeNow()}
            >
              {probeBusy ? "Проверяю…" : "Проверить сейчас"}
            </button>
          </div>
        </div>
        {healthOpen && health.length > 0 && (
          <div className="mt-2 max-h-56 space-y-1 overflow-y-auto">
            {health.map((h, i) => {
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
            })}
          </div>
        )}
      </div>
    </>
  );
}

function SettingsSection({'''

# Anchor: exact close of LogScrollPre + </> + func end
old = '</LogScrollPre>\n    </>\n  );\n}\n\nfunction SettingsSection({'

if old in t:
    t = t.replace(old, new_block, 1)
    changed = True
    print("[patch-bridge-health-ui] health block: ok")
else:
    print("[patch-bridge-health-ui] WARN: health anchor not found")

if changed:
    f.write_text(t)
print("[patch-bridge-health-ui] ok")
PY
