#!/usr/bin/env bash
# Add delete button to dead bridges in health list.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-health-delete] ERROR: $MAIN_TSX not found"; exit 1; }

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
        print(f"[patch-health-delete] {label}: ok")
    else:
        print(f"[patch-health-delete] WARN: {label} not found")

old_map = '''            {health.map((h, i) => {
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

new_map = '''            {health.map((h, i) => {
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
                      className="text-destructive text-[10px] hover:underline"
                      onClick={async () => {
                        if (!window.confirm("Удалить мёртвый мост\\n" + h.type + " " + h.addr + "\\n\\nНе отвечал при проверке.")) return;
                        try {
                          const res = await fetch("/api/settings/bridges", {
                            method: "PUT",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ action: "remove_dead", addr: h.addr }),
                          });
                          if (!res.ok) { const b = await res.json(); throw new Error(b.error || "HTTP " + res.status); }
                          const res2 = await fetch("/api/settings/bridges", { cache: "no-store" });
                          if (res2.ok) { const text = await res2.text(); const b2 = JSON.parse(text); if (b2.settings) setSettings((s) => ({ ...s, ...b2.settings })); }
                          setPoolHint("Мост удалён ✓");
                          setTimeout(() => setPoolHint(""), 3000);
                        } catch (e) {
                          setPoolHint(e instanceof Error ? e.message : "Ошибка удаления");
                          setTimeout(() => setPoolHint(""), 3000);
                        }
                      }}
                    >
                      ✕
                    </button>
                  )}
                </div>
              );
            })}'''

repl(old_map, new_map, "add delete to health list")

if changed:
    f.write_text(t)
print("[patch-health-delete] ok")
PY
