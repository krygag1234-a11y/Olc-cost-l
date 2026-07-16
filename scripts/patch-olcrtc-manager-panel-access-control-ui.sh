#!/usr/bin/env bash
# Olc-cost-l frontend: секция «Контроль доступа» в модалке общих настроек.
#   Настоящий allowlist по hwid устройства (olcbox шлёт x-hwid при запросе
#   подписки) + журнал попыток неизвестных устройств с кнопкой «Разрешить».
#   Работает с /api/access/{settings,attempts,allow,remove}.
# Idempotent. Target: manager src/main.tsx. Run after backup-ui.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-access-control-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Компонент AccessControlSection (перед ComponentSettingsModal) ---
comp_anchor = 'function ComponentSettingsModal({'
comp_block = r'''// ============================================================================
// Olc-cost-l: секция «Контроль доступа» — настоящий allowlist по hwid устройства.
// olcbox при запросе подписки шлёт заголовок x-hwid (стабильный per-install id).
// Известное устройство получает подписку (а значит и доступ к инстансам, т.к. без
// подписки нет room-креды); чужое — блокируется (режим enforce) и попадает в журнал.
// В отличие от «рандомизации пути» (её можно обойти, зная путь) — это реальный
// контроль. См. docs/ACCESS-CONTROL.md.
// !!! ПРИ ИЗМЕНЕНИИ формата access-control — учтите бэкап (backupExtraFiles) и API.
// ============================================================================
function AccessControlSection() {
  const [enabled, setEnabled] = useState(false);
  const [mode, setMode] = useState<"monitor" | "enforce">("monitor");
  const [allowed, setAllowed] = useState<string[]>([]);
  const [attempts, setAttempts] = useState<Array<Record<string, any>>>([]);
  const [newHwid, setNewHwid] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const loadAll = async () => {
    try {
      const s = await fetch("/api/access/settings", { cache: "no-store" });
      const sb = await s.json();
      setEnabled(!!sb.enabled);
      setMode(sb.mode === "enforce" ? "enforce" : "monitor");
      setAllowed(Array.isArray(sb.allowed_hwids) ? sb.allowed_hwids : []);
      const a = await fetch("/api/access/attempts", { cache: "no-store" });
      const ab = await a.json();
      setAttempts(Array.isArray(ab.attempts) ? ab.attempts.slice().reverse() : []);
    } catch {
      /* ignore */
    }
  };
  useEffect(() => { void loadAll(); }, []);

  const saveSettings = async (next: { enabled?: boolean; mode?: string }) => {
    setBusy(true); setMsg(null);
    try {
      const body = { enabled, mode, allowed_hwids: allowed, ...next };
      const res = await fetch("/api/access/settings", {
        method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
      });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : "monitor");
      setAllowed(Array.isArray(b.allowed_hwids) ? b.allowed_hwids : []);
    } catch (e: any) {
      setMsg("Ошибка: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  const allow = async (hwid: string) => {
    if (!hwid) return;
    setBusy(true); setMsg(null);
    try {
      const res = await fetch("/api/access/allow", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ hwid }),
      });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setAllowed(Array.isArray(b.allowed_hwids) ? b.allowed_hwids : []);
      setNewHwid("");
      await loadAll();
    } catch (e: any) {
      setMsg("Ошибка: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  const remove = async (hwid: string) => {
    setBusy(true); setMsg(null);
    try {
      const res = await fetch("/api/access/remove", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ hwid }),
      });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setAllowed(Array.isArray(b.allowed_hwids) ? b.allowed_hwids : []);
    } catch (e: any) {
      setMsg("Ошибка: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Контроль доступа (по устройству)</div>
      <div className="text-xs text-muted-foreground">
        Настоящий белый список: приложение olcbox при запросе подписки присылает
        идентификатор устройства (hwid). Разрешённые устройства получают доступ, чужие —
        блокируются и попадают в журнал ниже. Это надёжнее «рандомизации пути», которую
        можно обойти, зная путь. Данные хранятся только на этом сервере.
      </div>
      <label className="flex items-center gap-2 text-sm text-foreground">
        <input type="checkbox" checked={enabled} disabled={busy}
          onChange={(e) => { setEnabled(e.target.checked); void saveSettings({ enabled: e.target.checked }); }} />
        Включить контроль доступа
      </label>
      {enabled && (
        <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
          <label className="flex items-center gap-1">
            <input type="radio" name="olc-ac-mode" checked={mode === "monitor"} disabled={busy}
              onChange={() => { setMode("monitor"); void saveSettings({ mode: "monitor" }); }} />
            Только наблюдение (пускать всех, вести журнал)
          </label>
          <label className="flex items-center gap-1">
            <input type="radio" name="olc-ac-mode" checked={mode === "enforce"} disabled={busy}
              onChange={() => { setMode("enforce"); void saveSettings({ mode: "enforce" }); }} />
            Блокировать неизвестные устройства
          </label>
        </div>
      )}
      {enabled && (
        <>
          <div className="text-xs font-medium text-foreground">Разрешённые устройства (hwid)</div>
          {allowed.length === 0 && <div className="text-xs text-muted-foreground">Пока пусто. Добавьте hwid вручную или из журнала ниже.</div>}
          <div className="grid gap-1">
            {allowed.map((h) => (
              <div key={h} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-xs">
                <span className="truncate font-mono">{h}</span>
                <button type="button" className="text-red-400 hover:text-red-300" disabled={busy} onClick={() => void remove(h)}>✕</button>
              </div>
            ))}
          </div>
          <div className="flex gap-2">
            <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
              placeholder="install-… (hwid устройства)" value={newHwid} onChange={(e) => setNewHwid(e.target.value)} />
            <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={busy || !newHwid.trim()} onClick={() => void allow(newHwid.trim())}>Добавить</button>
          </div>

          <div className="flex items-center justify-between">
            <div className="text-xs font-medium text-foreground">Журнал попыток</div>
            <button type="button" className="rounded border border-border px-2 py-1 text-[11px] hover:bg-muted" disabled={busy} onClick={() => void loadAll()}>Обновить</button>
          </div>
          {attempts.length === 0 && <div className="text-xs text-muted-foreground">Попыток пока не зафиксировано.</div>}
          <div className="grid gap-1">
            {attempts.slice(0, 30).map((a, i) => {
              const hwid = String(a.hwid || "");
              const known = allowed.some((h) => h.toLowerCase() === hwid.toLowerCase());
              return (
                <div key={i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                  <div className="min-w-0">
                    <div className="truncate font-mono">{hwid || "(без hwid)"} {a.allowed ? "✓" : "✗"}</div>
                    <div className="truncate text-muted-foreground">{String(a.ip || "")} · {String(a.client_id || "")} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                  </div>
                  {!known && hwid && (
                    <button type="button" className="shrink-0 rounded border border-primary px-2 py-1 text-primary" disabled={busy} onClick={() => void allow(hwid)}>Разрешить</button>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}
      {msg && <div className="text-xs text-red-500 whitespace-pre-wrap">{msg}</div>}
    </section>
  );
}

'''
if 'function AccessControlSection()' in t:
    print("[patch-access-control-ui] component already present")
elif comp_anchor in t:
    t = t.replace(comp_anchor, comp_block + comp_anchor, 1); changed = True
    print("[patch-access-control-ui] added AccessControlSection component")
else:
    print("[patch-access-control-ui] WARN: ComponentSettingsModal anchor not found — skip component")

# --- 2. Рендер после <BackupSection /> (backup-ui выполняется раньше) ---
render_anchor = '            <BackupSection />'
render_add = render_anchor + '''

            <AccessControlSection />'''
if '<AccessControlSection />' in t:
    print("[patch-access-control-ui] already rendered")
elif render_anchor in t:
    t = t.replace(render_anchor, render_add, 1); changed = True
    print("[patch-access-control-ui] rendered <AccessControlSection /> after BackupSection")
else:
    print("[patch-access-control-ui] WARN: <BackupSection /> anchor not found — skip render (backup-ui must run first)")

if changed:
    f.write_text(t)
    print("[patch-access-control-ui] OK: main.tsx updated")
else:
    print("[patch-access-control-ui] no changes (idempotent)")
PY
