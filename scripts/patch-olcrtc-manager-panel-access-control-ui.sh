#!/usr/bin/env bash
# Olc-cost-l frontend: секция «Контроль доступа» в модалке общих настроек (v2).
#   Настоящий allowlist по hwid устройства + журнал попыток в СТИЛЕ ЛОГОВ:
#   - ограниченный по высоте прокручиваемый контейнер (страница не растёт бесконечно);
#   - адаптация под «автологи»: вкл → авто-обновление + вместо «Обновить» зелёная
#     ненажимная надпись «автологи»; выкл → кнопка «Обновить»;
#   - follow-newest со скроллбэком: листаешь вверх — пауза; вернулся вниз — через
#     ~1.5с снова follow за новыми;
#   - группировка (Count/«×N») — без спама повторами; кнопка «Очистить».
# Работает с /api/access/{settings,attempts,attempts/clear,allow,remove} и
# /api/settings/logs (состояние автологов). Idempotent. Target: src/main.tsx.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-access-control-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

comp_anchor = 'function ComponentSettingsModal({'
comp_block = r'''// ============================================================================
// Olc-cost-l: секция «Контроль доступа» — настоящий allowlist по hwid устройства.
// olcbox при запросе подписки шлёт заголовок x-hwid (стабильный per-install id).
// Разрешённое устройство получает подписку (и может брать её по ОРИГИНАЛЬНОМУ
// client-id даже при включённой рандомизации); чужое — блокируется (enforce) и
// попадает в журнал. Надёжнее «рандомизации пути». См. docs/ACCESS-CONTROL.md.
// !!! ПРИ ИЗМЕНЕНИИ формата access-control — учтите бэкап (backupExtraFiles) и API.
// ============================================================================
function AccessControlSection() {
  const [enabled, setEnabled] = useState(false);
  const [mode, setMode] = useState<"monitor" | "enforce">("monitor");
  const [allowed, setAllowed] = useState<string[]>([]);
  const [attempts, setAttempts] = useState<Array<Record<string, any>>>([]);
  const [connections, setConnections] = useState<Array<Record<string, any>>>([]);
  const [autolog, setAutolog] = useState(true);
  const [newHwid, setNewHwid] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const listRef = useRef<HTMLDivElement | null>(null);
  const followRef = useRef(true);
  const resumeRef = useRef<number | null>(null);

  const loadSettings = async () => {
    try {
      const s = await fetch("/api/access/settings", { cache: "no-store" });
      const sb = await s.json();
      setEnabled(!!sb.enabled);
      setMode(sb.mode === "enforce" ? "enforce" : "monitor");
      setAllowed(Array.isArray(sb.allowed_hwids) ? sb.allowed_hwids : []);
    } catch { /* ignore */ }
    try {
      const l = await fetch("/api/settings/logs", { cache: "no-store" });
      const lb = await l.json();
      setAutolog(lb.auto_refresh !== false);
    } catch { setAutolog(true); }
  };
  const loadAttempts = async () => {
    try {
      const a = await fetch("/api/access/attempts", { cache: "no-store" });
      const ab = await a.json();
      setAttempts(Array.isArray(ab.attempts) ? ab.attempts : []);
    } catch { /* ignore */ }
    try {
      const c = await fetch("/api/access/connections", { cache: "no-store" });
      const cb = await c.json();
      setConnections(Array.isArray(cb.connections) ? cb.connections : []);
    } catch { /* ignore */ }
  };
  const loadAll = async () => { await loadSettings(); await loadAttempts(); };

  useEffect(() => { void loadAll(); }, []);
  // Автообновление журнала при включённых автологах.
  useEffect(() => {
    if (!autolog) return;
    const id = window.setInterval(() => { void loadAttempts(); }, 2000);
    return () => window.clearInterval(id);
  }, [autolog]);
  // follow-newest: после обновления списка прокрутить вниз, если follow активен.
  useEffect(() => {
    if (followRef.current && listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [attempts]);

  const onScroll = () => {
    const el = listRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
    if (nearBottom) {
      if (resumeRef.current) window.clearTimeout(resumeRef.current);
      resumeRef.current = window.setTimeout(() => { followRef.current = true; }, 1500);
    } else {
      followRef.current = false;
      if (resumeRef.current) { window.clearTimeout(resumeRef.current); resumeRef.current = null; }
    }
  };

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
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const allow = async (hwid: string) => {
    if (!hwid) return;
    setBusy(true); setMsg(null);
    try {
      const res = await fetch("/api/access/allow", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ hwid }) });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setAllowed(Array.isArray(b.allowed_hwids) ? b.allowed_hwids : []);
      setNewHwid("");
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const remove = async (hwid: string) => {
    setBusy(true); setMsg(null);
    try {
      const res = await fetch("/api/access/remove", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ hwid }) });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setAllowed(Array.isArray(b.allowed_hwids) ? b.allowed_hwids : []);
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const clearAttempts = async () => {
    setBusy(true); setMsg(null);
    try {
      await fetch("/api/access/attempts/clear", { method: "POST" });
      followRef.current = true;
      await loadAttempts();
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };

  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Контроль доступа (по устройству)</div>
      <div className="text-xs text-muted-foreground">
        Настоящий белый список: olcbox при запросе подписки присылает идентификатор
        устройства (hwid). Разрешённые устройства получают доступ (в т.ч. по оригинальному
        client-id даже при включённой рандомизации), чужие — блокируются и попадают в
        журнал. Данные хранятся только на этом сервере.
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
          {allowed.length > 0 && (
            <div className="grid max-h-32 gap-1 overflow-y-auto">
              {allowed.map((h) => (
                <div key={h} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-xs">
                  <span className="truncate font-mono">{h}</span>
                  <button type="button" className="text-red-400 hover:text-red-300" disabled={busy} onClick={() => void remove(h)}>✕</button>
                </div>
              ))}
            </div>
          )}
          <div className="flex gap-2">
            <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
              placeholder="install-… (hwid устройства)" value={newHwid} onChange={(e) => setNewHwid(e.target.value)} />
            <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={busy || !newHwid.trim()} onClick={() => void allow(newHwid.trim())}>Добавить</button>
          </div>

          <div className="flex items-center justify-between">
            <div className="text-xs font-medium text-foreground">Журнал попыток</div>
            <div className="flex items-center gap-2">
              {autolog ? (
                <span className="rounded border border-emerald-700 px-2 py-1 text-[11px] text-emerald-400">● автологи</span>
              ) : (
                <button type="button" className="rounded border border-border px-2 py-1 text-[11px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>
              )}
              <button type="button" className="rounded border border-border px-2 py-1 text-[11px] hover:bg-muted" disabled={busy} onClick={() => void clearAttempts()}>Очистить</button>
            </div>
          </div>
          {attempts.length === 0 && <div className="text-xs text-muted-foreground">Попыток пока не зафиксировано.</div>}
          {attempts.length > 0 && (
            <div ref={listRef} onScroll={onScroll} className="grid max-h-56 gap-1 overflow-y-auto rounded border border-border bg-card/40 p-2">
              {attempts.map((a, i) => {
                const hwid = String(a.hwid || "");
                const known = allowed.some((h) => h.toLowerCase() === hwid.toLowerCase());
                const count = Number(a.count || 1);
                return (
                  <div key={hwid + "|" + String(a.client_id) + "|" + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                    <div className="min-w-0">
                      <div className="truncate font-mono">
                        {hwid || "(без hwid)"} {a.allowed ? "✓" : "✗"}
                        {count > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{count}</span>}
                      </div>
                      <div className="truncate text-muted-foreground">{String(a.ip || "")} · {String(a.client_id || "")} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                    </div>
                    {!known && hwid && (
                      <button type="button" className="shrink-0 rounded border border-primary px-2 py-1 text-primary" disabled={busy} onClick={() => void allow(hwid)}>Разрешить</button>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}
      {enabled && connections.length > 0 && (
        <>
          <div className="text-xs font-medium text-foreground">Устройства, подключавшиеся к инстансам</div>
          <div className="text-[11px] text-muted-foreground">Идентификатор устройства (device) из логов подключения — тот же, что hwid подписки. Можно добавить в allowlist.</div>
          <div className="grid max-h-40 gap-1 overflow-y-auto rounded border border-border bg-card/40 p-2">
            {connections.map((c, i) => {
              const dev = String(c.device || "");
              const known = allowed.some((h) => h.toLowerCase() === dev.toLowerCase());
              const count = Number(c.count || 1);
              return (
                <div key={dev + "|" + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                  <div className="min-w-0">
                    <div className="truncate font-mono">{dev} {known && <span className="text-emerald-400">✓</span>}{count > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{count}</span>}</div>
                    <div className="truncate text-muted-foreground">последнее: {String(c.last || "").slice(0, 19)}</div>
                  </div>
                  {!known && dev && (
                    <button type="button" className="shrink-0 rounded border border-primary px-2 py-1 text-primary" disabled={busy} onClick={() => void allow(dev)}>Разрешить</button>
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

render_anchor = '            <BackupSection />'
render_add = render_anchor + '''

            <AccessControlSection />'''
if '<AccessControlSection />' in t:
    print("[patch-access-control-ui] already rendered")
elif render_anchor in t:
    t = t.replace(render_anchor, render_add, 1); changed = True
    print("[patch-access-control-ui] rendered <AccessControlSection /> after BackupSection")
else:
    print("[patch-access-control-ui] WARN: <BackupSection /> anchor not found — skip render")

if changed:
    f.write_text(t)
    print("[patch-access-control-ui] OK: main.tsx updated")
else:
    print("[patch-access-control-ui] no changes (idempotent)")
PY
