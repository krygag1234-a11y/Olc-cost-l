#!/usr/bin/env bash
# Olc-cost-l frontend: per-client контроль доступа (шестерёнка у кнопки 🎲).
# Кнопка ⚙ рядом с рандомизацией на карточке клиента открывает модалку доступа для
# ЭТОЙ подписки: режим (наследовать/выкл/наблюдение/блокировать), белый список и бан
# устройств, журнал попыток по этому клиенту. Работает с /api/access/client.
# Idempotent. Target: manager src/main.tsx. Run near конца, после randomization-ui.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-client-access-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Компонент ClientAccessModal (перед ComponentSettingsModal) ---
comp_anchor = 'function ComponentSettingsModal({'
comp_block = r'''// ============================================================================
// Olc-cost-l: per-client контроль доступа к подписке (модалка по шестерёнке у 🎲).
// Индивидуально для ОДНОЙ подписки: режим, белый список (allow) и бан устройств.
// Забаненные не получат подписку даже если разрешены глобально. См. docs/ACCESS-CONTROL.md.
// ============================================================================
function ClientAccessModal({ clientId, onClose }: { clientId: string; onClose: () => void }) {
  type Dev = { hwid: string; label?: string; enabled: boolean };
  const [mode, setMode] = useState<string>("inherit");
  const [allow, setAllow] = useState<Dev[]>([]);
  const [ban, setBan] = useState<Dev[]>([]);
  const [attempts, setAttempts] = useState<Array<Record<string, any>>>([]);
  const [newAllow, setNewAllow] = useState("");
  const [newBan, setNewBan] = useState("");
  const [autolog, setAutolog] = useState(true);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const load = async () => {
    try {
      const r = await fetch(`/api/access/client?client_id=${encodeURIComponent(clientId)}`, { cache: "no-store" });
      const b = await r.json();
      setMode(b.mode || "inherit");
      setAllow(Array.isArray(b.allow) ? b.allow : []);
      setBan(Array.isArray(b.ban) ? b.ban : []);
    } catch { /* ignore */ }
    try {
      const l = await fetch("/api/settings/logs", { cache: "no-store" });
      const lb = await l.json();
      setAutolog(lb.auto_refresh !== false);
    } catch { setAutolog(true); }
    await loadAttempts();
  };
  const loadAttempts = async () => {
    try {
      const a = await fetch("/api/access/attempts", { cache: "no-store" });
      const ab = await a.json();
      setAttempts((Array.isArray(ab.attempts) ? ab.attempts : []).filter((x: any) => String(x.client_id) === clientId));
    } catch { /* ignore */ }
  };
  useEffect(() => { void load(); }, [clientId]);
  useEffect(() => {
    if (!autolog) return;
    const id = window.setInterval(() => { void loadAttempts(); }, 2500);
    return () => window.clearInterval(id);
  }, [autolog, clientId]);
  const clearLog = async () => {
    setBusy(true); setMsg(null);
    try {
      await fetch(`/api/access/attempts/clear?client_id=${encodeURIComponent(clientId)}`, { method: "POST" });
      await loadAttempts();
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };

  const save = async (next?: { mode?: string; allow?: Dev[]; ban?: Dev[] }) => {
    setBusy(true); setMsg(null);
    try {
      const body = { client_id: clientId, mode, allow, ban, ...next };
      const r = await fetch("/api/access/client", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
      const cc = (b.clients || {})[clientId] || { mode: "inherit", allow: [], ban: [] };
      setMode(cc.mode || "inherit");
      setAllow(Array.isArray(cc.allow) ? cc.allow : []);
      setBan(Array.isArray(cc.ban) ? cc.ban : []);
      await load();
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const addAllow = (h: string) => { h = h.trim(); if (!h) return; void save({ allow: [...allow, { hwid: h, enabled: true }] }); setNewAllow(""); };
  const addBan = (h: string) => { h = h.trim(); if (!h) return; void save({ ban: [...ban, { hwid: h, enabled: true }] }); setNewBan(""); };
  const rmAllow = (h: string) => void save({ allow: allow.filter((d) => d.hwid !== h) });
  const rmBan = (h: string) => void save({ ban: ban.filter((d) => d.hwid !== h) });
  const toggleAllow = (h: string, en: boolean) => void save({ allow: allow.map((d) => d.hwid === h ? { ...d, enabled: en } : d) });
  const toggleBan = (h: string, en: boolean) => void save({ ban: ban.map((d) => d.hwid === h ? { ...d, enabled: en } : d) });

  const devRow = (d: Dev, onToggle: ((en: boolean) => void) | null, onRemove: () => void) => (
    <div key={d.hwid} className="flex items-center gap-2 rounded border border-border px-2 py-1 text-[11px]">
      {onToggle && <input type="checkbox" title="вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => onToggle(e.target.checked)} />}
      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.label ? d.label + " · " : ""}{d.hwid}</span>
      <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={onRemove}>✕</button>
    </div>
  );

  return (
    <Modal title={`Доступ к подписке: ${clientId}`} onClose={onClose}>
      <div className="grid gap-3 p-4 text-sm">
        <div className="text-xs text-muted-foreground">
          Индивидуальный контроль доступа для этой подписки. «Наследовать» — как в
          глобальных настройках. Забаненные устройства не получат подписку, даже если
          разрешены глобально. Идентификатор устройства (hwid) olcbox шлёт при запросе.
        </div>
        <label className="grid gap-1 text-xs text-muted-foreground">
          Режим для этой подписки
          <select className="h-9 rounded border border-border bg-card px-2 text-foreground" value={mode} disabled={busy}
            onChange={(e) => { setMode(e.target.value); void save({ mode: e.target.value }); }}>
            <option value="inherit">Наследовать глобальный</option>
            <option value="off">Выключен (пускать всех)</option>
            <option value="monitor">Наблюдение (лог, пускать)</option>
            <option value="enforce">Блокировать неизвестные</option>
          </select>
        </label>

        <div className="text-xs font-medium text-emerald-400">✅ Разрешённые (только для этой подписки)</div>
        {allow.length === 0 && <div className="text-xs text-muted-foreground">Пусто — используется глобальный список.</div>}
        <div className="grid max-h-32 gap-1 overflow-y-auto">{allow.map((d) => devRow(d, (en) => toggleAllow(d.hwid, en), () => rmAllow(d.hwid)))}</div>
        <div className="flex gap-2">
          <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (разрешить)" value={newAllow} onChange={(e) => setNewAllow(e.target.value)} />
          <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={busy || !newAllow.trim()} onClick={() => addAllow(newAllow)}>Разрешить</button>
        </div>

        <div className="text-xs font-medium text-red-400">🚫 Забаненные (только для этой подписки)</div>
        {ban.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
        <div className="grid max-h-32 gap-1 overflow-y-auto">{ban.map((d) => devRow(d, (en) => toggleBan(d.hwid, en), () => rmBan(d.hwid)))}</div>
        <div className="flex gap-2">
          <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (забанить)" value={newBan} onChange={(e) => setNewBan(e.target.value)} />
          <button type="button" className="rounded-md border border-red-500/40 bg-red-500/10 px-3 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" disabled={busy || !newBan.trim()} onClick={() => addBan(newBan)}>Забанить</button>
        </div>

        <div className="flex items-center justify-between">
          <div className="text-xs font-medium text-foreground">📋 Попытки по этой подписке</div>
          <div className="flex items-center gap-2">
            {autolog
              ? <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
              : <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>}
            <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearLog()}>Очистить</button>
          </div>
        </div>
        {attempts.length === 0 && <div className="text-xs text-muted-foreground">Пока нет.</div>}
        <div className="grid max-h-40 gap-1 overflow-y-auto rounded border border-border bg-card/40 p-2">
          {attempts.map((a, i) => {
            const hwid = String(a.hwid || "");
            const known = allow.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase());
            const banned = ban.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase());
            return (
              <div key={hwid + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                <div className="min-w-0">
                  <div className="truncate font-mono">{hwid || "(без hwid)"} {a.allowed ? "✓" : "✗"}{Number(a.count || 1) > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{a.count}</span>}</div>
                  <div className="truncate text-muted-foreground">{String(a.ip || "")} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                </div>
                {hwid && (
                  <div className="flex shrink-0 gap-1">
                    {!known && <button type="button" className="rounded border border-primary px-2 py-1 text-primary" disabled={busy} onClick={() => addAllow(hwid)}>Разрешить</button>}
                    {!banned && <button type="button" className="rounded border border-red-500/40 px-2 py-1 text-red-400" disabled={busy} onClick={() => addBan(hwid)}>Бан</button>}
                  </div>
                )}
              </div>
            );
          })}
        </div>
        {msg && <div className="text-xs text-red-500 whitespace-pre-wrap">{msg}</div>}
      </div>
    </Modal>
  );
}

'''
if 'function ClientAccessModal(' in t:
    print("[patch-client-access-ui] component already present")
elif comp_anchor in t:
    t = t.replace(comp_anchor, comp_block + comp_anchor, 1); changed = True
    print("[patch-client-access-ui] added ClientAccessModal component")
else:
    print("[patch-client-access-ui] WARN: ComponentSettingsModal anchor not found — skip component")

# --- 2. Состояние accessClient (после globalRandomizationEnabled) ---
state_anchor = 'const [globalRandomizationEnabled, setGlobalRandomizationEnabled] = useState(false);'
if 'const [accessClient, setAccessClient]' in t:
    print("[patch-client-access-ui] state already present")
elif state_anchor in t:
    t = t.replace(state_anchor, state_anchor + '\n  const [accessClient, setAccessClient] = useState<string | null>(null);', 1); changed = True
    print("[patch-client-access-ui] added accessClient state")
else:
    print("[patch-client-access-ui] WARN: globalRandomizationEnabled state anchor not found")

# --- 3. Кнопка-шестерёнка после кнопки 🎲 ---
gear_anchor = '''                        🎲 {client.randomization?.enabled || globalRandomizationEnabled ? "ON" : "OFF"}
                      </button>'''
gear_add = gear_anchor + '''
                      <button
                        className="inline-flex h-8 items-center gap-1 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        title="Контроль доступа к этой подписке (устройства)"
                        onClick={() => setAccessClient(client.client_id)}
                      >
                        ⚙
                      </button>'''
if 'setAccessClient(client.client_id)' in t:
    print("[patch-client-access-ui] gear button already present")
elif gear_anchor in t:
    t = t.replace(gear_anchor, gear_add, 1); changed = True
    print("[patch-client-access-ui] added gear button")
else:
    print("[patch-client-access-ui] WARN: 🎲 button anchor not found (randomization-ui must run first)")

# --- 4. Рендер модалки (перед {showSettings && () ---
render_anchor = '      {showSettings && ('
render_add = '      {accessClient && <ClientAccessModal clientId={accessClient} onClose={() => setAccessClient(null)} />}\n      {showSettings && ('
if '<ClientAccessModal ' in t:
    print("[patch-client-access-ui] modal render already present")
elif render_anchor in t:
    t = t.replace(render_anchor, render_add, 1); changed = True
    print("[patch-client-access-ui] rendered ClientAccessModal")
else:
    print("[patch-client-access-ui] WARN: showSettings anchor not found")

if changed:
    f.write_text(t)
    print("[patch-client-access-ui] OK: main.tsx updated")
else:
    print("[patch-client-access-ui] no changes (idempotent)")
PY
