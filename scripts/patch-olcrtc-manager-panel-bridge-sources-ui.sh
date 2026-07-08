#!/usr/bin/env bash
# Phase 1 — bridge sources UI in BridgesSettingsFields.
# Must run AFTER bridge-health-ui. Anchors on health block or end of func.
# Idempotent. Target: manager src/main.tsx.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-bridge-sources-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-bridge-sources-ui] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-bridge-sources-ui] {label}: ok")
    else:
        print(f"[patch-bridge-sources-ui] WARN {label}: anchor not found (len={len(old)})")

# --- 1. Add sources state + fetch/save ---
repl(
    '  const [poolHint, setPoolHint] = useState("");',
    '''  const [poolHint, setPoolHint] = useState("");
  // --- Sources management ---
  const [sources, setSources] = useState<Record<string, unknown>[]>([]);
  const [sourcesBusy, setSourcesBusy] = useState(false);
  const [addSourceUrl, setAddSourceUrl] = useState("");
  const [addSourceLabel, setAddSourceLabel] = useState("");
  const loadSources = async () => {
    try {
      const res = await fetch("/api/sources/bridges");
      if (!res.ok) return;
      const body = await res.json() as { sources?: Record<string, unknown>[]; error?: string };
      if (body.sources) setSources(body.sources);
    } catch { /* ignore */ }
  };
  const saveSources = async () => {
    setSourcesBusy(true);
    try {
      const res = await fetch("/api/sources/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sources }),
      });
      const body = await res.json() as { sources?: Record<string, unknown>[]; error?: string };
      if (!res.ok) { setPoolHint(body.error || `HTTP ${res.status}`); }
      else {
        if (body.sources) setSources(body.sources);
        await onReload();
        setPoolHint("Источники обновлены ✓");
      }
    } catch (e) {
      setPoolHint(e instanceof Error ? e.message : "Ошибка источника");
    } finally {
      setSourcesBusy(false);
    }
  };
  const enableSource = (id: string) => {
    setSources((ss) => ss.map((s) => {
      const m = { ...s } as Record<string, unknown>;
      if (String(m.id) === id) m.enabled = !m.enabled;
      return m;
    }));
  };
  const removeSource = (id: string) => {
    setSources((ss) => ss.filter((s) => String(s.id) !== id));
  };
  const addNewSource = () => {
    if (!addSourceUrl.trim()) return;
    const entry: Record<string, unknown> = {
      id: "custom-" + Date.now().toString(36),
      url: addSourceUrl.trim(),
      label: addSourceLabel.trim() || addSourceUrl.trim().slice(0, 60),
      enabled: true,
      editable: true,
    };
    setSources((ss) => [...ss, entry]);
    setAddSourceUrl("");
    setAddSourceLabel("");
  };''',
    "sources state + management",
    guard='const loadSources = async () =>',
)

# --- 2. Add sources section AFTER health block or end of func ---
# Anchor: the end of Health Check </div> + closing tags + SettingsSection
anchor_a = '''        )}
      </div>
    </>
  );
}

function SettingsSection({'''

new_a = '''        )}
      </div>
      {/* --- Sources Management --- */}
      <section className="rounded-lg border border-border bg-muted/10 p-2.5 text-xs">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="font-semibold text-foreground">Источники мостов</h3>
          <div className="flex items-center gap-1.5">
            <span className="text-[10px] text-muted-foreground">{sources.filter((s) => (s as Record<string, unknown>).enabled).length}/{sources.length} активно</span>
            <button
              type="button"
              className="rounded border border-border px-2 py-1 hover:bg-muted disabled:opacity-50"
              disabled={sourcesBusy}
              onClick={() => void saveSources()}
            >
              {sourcesBusy ? "…" : "Применить"}
            </button>
          </div>
        </div>
        <div className="space-y-1">
          {sources.map((s) => {
            const id = String(s.id ?? "");
            const enabled = Boolean((s as Record<string, unknown>).enabled);
            const label = String((s as Record<string, unknown>).label ?? id);
            const url = String((s as Record<string, unknown>).url ?? "");
            const editable = Boolean((s as Record<string, unknown>).editable);
            return (
              <div key={id} className="flex items-start gap-2 rounded bg-background/60 px-2 py-1.5">
                <input
                  type="checkbox"
                  className="mt-0.5 rounded border-border"
                  checked={enabled}
                  onChange={() => void enableSource(id)}
                />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-foreground">{label}</div>
                  <div className="font-mono text-[10px] text-muted-foreground truncate" title={url}>{url}</div>
                </div>
                {editable && (
                  <button
                    type="button"
                    className="text-destructive text-[10px] hover:underline shrink-0"
                    onClick={() => void removeSource(id)}
                  >
                    ✕
                  </button>
                )}
              </div>
            );
          })}
        </div>
        <div className="mt-2 rounded border border-dashed border-border bg-background/50 p-2">
          <div className="mb-1 text-[10px] font-medium text-muted-foreground">Добавить источник</div>
          <div className="grid gap-1.5">
            <input
              className="h-7 rounded border border-border bg-background px-2 text-[10px]"
              placeholder="Название"
              value={addSourceLabel}
              onChange={(e) => setAddSourceLabel(e.target.value)}
            />
            <input
              className="h-7 rounded border border-border bg-background px-2 font-mono text-[10px]"
              placeholder="https://example.com/bridges.txt"
              value={addSourceUrl}
              onChange={(e) => setAddSourceUrl(e.target.value)}
            />
            <button
              type="button"
              className="rounded border border-primary px-2 py-1 text-[10px] text-primary hover:bg-primary/10"
              onClick={() => void addNewSource()}
            >
              Добавить
            </button>
          </div>
        </div>
      </section>
    </>
  );
}

function SettingsSection({'''

# Try: anchor on end of Health Check block (if health already applied)
if anchor_a in t:
    t = t.replace(anchor_a, new_a, 1)
    changed = True
    print("[patch-bridge-sources-ui] sources section: ok (after health)")
elif 'Источники мостов' in t:
    print("[patch-bridge-sources-ui] sources section: already applied")
else:
    print("[patch-bridge-sources-ui] WARN: anchor not found")

if changed:
    f.write_text(t)
print("[patch-bridge-sources-ui] ok")
PY
