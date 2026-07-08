#!/usr/bin/env bash
# Phase 1: Fix delete dead bridge + better profiles UI.
# Uses exact anchors from original main.tsx.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-bridge-fix-final] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-bridge-fix-final] {label}: already")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-bridge-fix-final] {label}: ok")
    else:
        print(f"[patch-bridge-fix-final] WARN: {label} not found (len={len(old)})")

# === FIX 1: Delete dead bridge - correct fetch + reload ===
old_delete = '''{alive === false && checked && (
                    <button
                      type="button"
                      className="text-destructive text-[10px] hover:underline hover:text-destructive/80"
                      onClick={async () => {
                        if (!window.confirm("Удалить мёртвый мост?\\n" + h.addr)) return;
                        try {
                          const res = await fetch("/api/settings/bridges", {
                            method: "PUT",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ action: "remove_dead", addr: h.addr }),
                          });
                          if (!res.ok) { const b = await res.json(); throw new Error(b.error || "HTTP " + res.status); }
                          // Reload health after delete
                          const res2 = await fetch("/api/settings/bridges", { cache: "no-store" });
                          if (res2.ok) {
                            const text = await res2.text();
                            const b2 = JSON.parse(text);
                            if (b2.settings) setSettings((s) => ({ ...s, ...b2.settings }));
                            setPoolHint("Мост удалён ✓");
                            setTimeout(() => setPoolHint(""), 3000);
                          }
                        } catch (e) {
                          setPoolHint(e instanceof Error ? e.message : "Ошибка удаления");
                          setTimeout(() => setPoolHint(""), 3000);
                        }
                      }}
                    >
                      ✕
                    </button>
                  )}'''

new_delete = '''{alive === false && checked && (
                    <button
                      type="button"
                      className="text-destructive text-[10px] hover:underline hover:text-destructive/80"
                      onClick={async () => {
                        if (!window.confirm("Удалить мёртвый мост\\n" + h.type + " " + h.addr + "\\n\\nНе отвечал при проверке.")) return;
                        try {
                          const res = await fetch("/api/settings/bridges", {
                            method: "PUT",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({ action: "remove_dead", addr: h.addr }),
                          });
                          if (!res.ok) { const b = await res.json(); throw new Error(b.error || "HTTP " + res.status); }
                          // Reload health
                          const res2 = await fetch("/api/settings/bridges", { cache: "no-store" });
                          if (res2.ok) {
                            const text = await res2.text();
                            const b2 = JSON.parse(text);
                            if (b2.settings) setSettings((s) => ({ ...s, ...b2.settings }));
                            setPoolHint("Мост удалён ✓");
                            setTimeout(() => setPoolHint(""), 3000);
                          }
                        } catch (e) {
                          setPoolHint(e instanceof Error ? e.message : "Ошибка удаления");
                          setTimeout(() => setPoolHint(""), 3000);
                        }
                      }}
                    >
                      ✕
                    </button>
                  )}'''

repl(old_delete, new_delete, "fix delete", "fix delete")

# === FIX 2: Better profiles UI ===
# Replace the profile section with visible form and card-based profile picker
old_profiles = '''      <label className="grid gap-1 text-xs text-muted-foreground">
        Активный профиль
        <select
          className="h-8 rounded border border-border bg-background px-2"
          value={activeId}
          onChange={(e) => patchProfiles({ ...prof, active_profile: e.target.value })}
        >
          <option value="system">Оригинальный (системный)</option>
          {custom.map((pr) => (
            <option key={String(pr.id)} value={String(pr.id)}>
              {String(pr.label ?? pr.id)}
            </option>
          ))}
        </select>
      </label>
      <div className="rounded border border-border p-3 text-xs space-y-2">
        <div className="font-medium">Оригинальный профиль</div>
        <p className="text-muted-foreground">Нельзя удалить. Обновляется из встроенных источников Olc-cost-l.</p>
        <label className="grid gap-1">
          Типы мостов
          <select
            className="h-8 rounded border border-border bg-background px-2"
            value={String(sys.types ?? "obfs4,webtunnel")}
            onChange={(e) => patchProfiles({ ...prof, system: { ...sys, types: e.target.value } })}
          >
            <option value="obfs4">obfs4</option>
            <option value="webtunnel">webTunnel</option>
            <option value="obfs4,webtunnel">obfs4 + webTunnel</option>
          </select>
        </label>
        <label className="flex items-center gap-2">
          <input
            type="checkbox"
            checked={Boolean(sys.auto_update)}
            onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })}
          />
          Автообновление (cron)
        </label>
        {!Boolean(sys.auto_update) && (
          <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" disabled={poolBusy || jobStatus === "running"} onClick={() => void refreshPool(String(sys.types ?? "obfs4,webtunnel"))}>
            Обновить сейчас
          </button>
        )}
      </div>
      {custom.length > 0 && (
        <div className="space-y-2 text-xs">
          <div className="font-medium">Свои профили</div>
          {custom.map((pr) => (
            <div key={String(pr.id)} className="flex items-center justify-between rounded border border-border px-2 py-1">
              <span>
                {String(pr.label ?? pr.id)} ({String(pr.mode ?? "?")})
              </span>
              <button type="button" className="text-destructive hover:underline" onClick={() => removeProfile(String(pr.id))}>
                Удалить
              </button>
            </div>
          ))}
        </div>
      )}
      <div className="flex flex-wrap gap-2">
        <button type="button" className="rounded border border-border px-2 py-1 text-xs" onClick={() => setAddMode("manual")}>
          + Свои мосты
        </button>
        <button type="button" className="rounded border border-border px-2 py-1 text-xs" onClick={() => setAddMode("url")}>
          + Ссылка (raw)
        </button>
      </div>
      {addMode === "manual" && (
        <div className="rounded border border-dashed border-border p-2 space-y-2 text-xs">
          <input className="h-8 w-full rounded border border-border bg-background px-2" placeholder="Название профиля" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} />
          <textarea className="min-h-[80px] w-full rounded border border-border bg-background p-2 font-mono" placeholder="Bridge obfs4 ...&#10;Bridge webtunnel ..." value={newBridges} onChange={(e) => setNewBridges(e.target.value)} />
          <button type="button" className="rounded border border-primary px-2 py-1 text-primary" onClick={addCustomProfile}>
            Добавить профиль
          </button>
        </div>
      )}
      {addMode === "url" && (
        <div className="rounded border border-dashed border-border p-2 space-y-2 text-xs">
          <input className="h-8 w-full rounded border border-border bg-background px-2" placeholder="Название профиля" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} />
          <textarea className="min-h-[60px] w-full rounded border border-border bg-background p-2 font-mono" placeholder="https://.../bridges.txt (по строке)" value={newUrls} onChange={(e) => setNewUrls(e.target.value)} />
          <p className="text-muted-foreground">Формат raw: одна ссылка на строку, как на GitHub.</p>
          <button type="button" className="rounded border border-primary px-2 py-1 text-primary" onClick={addCustomProfile}>
            Добавить профиль
          </button>
        </div>
      )}'''

new_profiles = '''      {/* Profile selector + create */}
      <div className="rounded-lg border border-border bg-muted/10 p-2.5 text-xs space-y-2">
        <div className="mb-1 font-semibold text-foreground">Профили мостов</div>

        {/* System profile */}
        <div className={`rounded border p-2 ${activeId === "system" ? "border-primary bg-primary/5" : "border-border bg-background"}`}>
          <div className="flex items-center justify-between">
            <div>
              <div className="font-medium">
                <span className="inline-block h-2 w-2 rounded-full bg-blue-400 mr-1"></span>
                Оригинальный (системный)
              </div>
              <div className="text-[10px] text-muted-foreground">Из встроенных источников</div>
            </div>
            <input type="radio" name="profile" checked={activeId === "system"} onChange={() => patchProfiles({ ...prof, active_profile: "system" })} />
          </div>
        </div>

        {/* Custom profile cards */}
        {custom.map((pr) => {
          const id = String(pr.id);
          const isSelected = activeId === id;
          const label = String(pr.label ?? id);
          const mode = String(pr.mode ?? "?");
          const bridgeCount = String((pr.bridges as string) ?? "").split("\\n").filter((l: string) => l.trim().startsWith("Bridge")).length;
          return (
            <div key={id} className={`rounded border p-2 ${isSelected ? "border-primary bg-primary/5" : "border-border bg-background"}`}>
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-medium">
                    <span className={`inline-block h-2 w-2 rounded-full mr-1 ${mode === "manual" ? "bg-green-400" : "bg-amber-400"}`}></span>
                    {label}
                  </div>
                  <div className="text-[10px] text-muted-foreground">
                    {bridgeCount > 0 ? bridgeCount + " мост" : "через URL"} · {mode === "manual" ? "ручные" : "источники"}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <input type="radio" name="profile" checked={isSelected} onChange={() => patchProfiles({ ...prof, active_profile: id })} />
                  <button type="button" className="text-destructive text-[10px] hover:underline" onClick={() => removeProfile(id)}>✕</button>
                </div>
              </div>
            </div>
          );
        })}

        {/* Create new profile (always visible) */}
        <div className="rounded border border-border bg-background p-2">
          <div className="mb-1 font-medium text-primary">Создать профиль</div>
          <input
            className="h-7 w-full rounded border border-border bg-background px-2 text-xs mb-1"
            placeholder="Название"
            value={newLabel}
            onChange={(e) => setNewLabel(e.target.value)}
          />
          <div className="flex gap-1 mb-1">
            <button type="button" className={`rounded border px-2 py-1 text-[10px] ${addMode === "" || addMode === "manual" ? "border-primary text-primary" : "border-border hover:bg-muted"}`} onClick={() => setAddMode("manual")}>Ручной (Bridge ...)</button>
            <button type="button" className={`rounded border px-2 py-1 text-[10px] ${addMode === "url" ? "border-primary text-primary" : "border-border hover:bg-muted"}`} onClick={() => setAddMode("url")}>URL (ссылка)</button>
          </div>
          {addMode === "manual" && (
            <textarea
              className="min-h-[60px] w-full rounded border border-border bg-background p-2 font-mono text-xs mb-1"
              placeholder="Bridge obfs4 ...&#10;Bridge webtunnel ..."
              value={newBridges}
              onChange={(e) => setNewBridges(e.target.value)}
            />
          )}
          {addMode === "url" && (
            <textarea
              className="min-h-[50px] w-full rounded border border-border bg-background p-2 font-mono text-xs mb-1"
              placeholder="https://.../bridges.txt (по строке)"
              value={newUrls}
              onChange={(e) => setNewUrls(e.target.value)}
            />
          )}
          <button type="button" className="rounded border border-primary px-2 py-1 text-xs text-primary hover:bg-primary/10" onClick={addCustomProfile}>Создать</button>
        </div>
      </div>'''

repl(old_profiles, new_profiles, "rewrite profiles UI", "rewrite profiles UI")

if changed:
    f.write_text(t)
print("[patch-bridge-fix-final] ok")
PY
