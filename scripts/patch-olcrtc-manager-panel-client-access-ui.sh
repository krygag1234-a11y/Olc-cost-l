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
  const [mode, setMode] = useState<string>("off");
  const [allow, setAllow] = useState<Dev[]>([]);
  const [ban, setBan] = useState<Dev[]>([]);
  const [connAllow, setConnAllow] = useState<Dev[]>([]);
  const [connBan, setConnBan] = useState<Dev[]>([]);
  const [hiddenCross, setHiddenCross] = useState<string[]>(() => { try { return JSON.parse(localStorage.getItem("olc-cross-hidden-v1") || "[]"); } catch { return []; } });
  const hideCross = (k: string) => { const nx = Array.from(new Set([...hiddenCross, k])); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const unhideCross = (k: string) => { const nx = hiddenCross.filter((x) => x !== k); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const [allowIps, setAllowIps] = useState<string[]>([]);
  const [banNoHwid, setBanNoHwid] = useState(false);
  const [newIp, setNewIp] = useState("");
  const [attempts, setAttempts] = useState<Array<Record<string, any>>>([]);
  const [connections, setConnections] = useState<Array<Record<string, any>>>([]);
  const [connClearedAt, setConnClearedAt] = useState<string>("");
  const aListRef = useRef<HTMLDivElement | null>(null);
  const aFollowRef = useRef(true);
  const aResumeRef = useRef<number | null>(null);
  const kListRef = useRef<HTMLDivElement | null>(null);
  const kFollowRef = useRef(true);
  const kResumeRef = useRef<number | null>(null);
  const [newAllow, setNewAllow] = useState("");
  const [newBan, setNewBan] = useState("");
  const [newConnAllow, setNewConnAllow] = useState("");
  const [newConnBan, setNewConnBan] = useState("");
  const [autolog, setAutolog] = useState(true);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [connEnforce, setConnEnforce] = useState(false);
  const [connScope, setConnScope] = useState<"all" | "selective">("all");
  const [connInstances, setConnInstances] = useState<string[]>([]);
  const [globalEnforceConns, setGlobalEnforceConns] = useState(false);
  const [glob, setGlob] = useState<any>({ devices: [], ban: [], allow_ips: [], conn_devices: [], conn_ban: [] });
  const [syncHidden, setSyncHidden] = useState<boolean>(() => { try { return localStorage.getItem("olc-sync-hidden-" + clientId) === "1"; } catch { return false; } });
  const [instances, setInstances] = useState<Array<{ room_id: string; name: string }>>([]);

  const load = async () => {
    try {
      const r = await fetch(`/api/access/client?client_id=${encodeURIComponent(clientId)}`, { cache: "no-store" });
      const b = await r.json();
      setMode(b.mode && b.mode !== "inherit" ? b.mode : "off");
      setAllow(Array.isArray(b.allow) ? b.allow : []);
      setBan(Array.isArray(b.ban) ? b.ban : []);
      setConnAllow(Array.isArray(b.conn_allow) ? b.conn_allow : []);
      setConnBan(Array.isArray(b.conn_ban) ? b.conn_ban : []);
      setAllowIps(Array.isArray(b.allow_ips) ? b.allow_ips : []);
      setBanNoHwid(!!b.ban_no_hwid);
      setConnEnforce(!!b.conn_enforce);
      setConnScope(b.conn_scope === "selective" ? "selective" : "all");
      setConnInstances(Array.isArray(b.conn_instances) ? b.conn_instances : []);
    } catch { /* ignore */ }
    try {
      const s = await fetch("/api/access/settings", { cache: "no-store" });
      const sb = await s.json();
      setGlobalEnforceConns(!!sb.enforce_connections);
      setGlob({
        devices: Array.isArray(sb.devices) ? sb.devices : [],
        ban: Array.isArray(sb.ban) ? sb.ban : [],
        allow_ips: Array.isArray(sb.allowed_ips) ? sb.allowed_ips : [],
        conn_devices: Array.isArray(sb.conn_devices) ? sb.conn_devices : [],
        conn_ban: Array.isArray(sb.conn_ban) ? sb.conn_ban : [],
      });
    } catch { /* ignore */ }
    try {
      const st = await fetch("/api/state", { cache: "no-store" });
      const stb = await st.json();
      const cl = (stb.clients || []).find((c: any) => String(c.client_id) === clientId);
      setInstances((cl?.locations || []).map((l: any) => ({ room_id: String(l.room_id || ""), name: String(l.name || l.room_id || "") })));
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
    try {
      const c = await fetch("/api/access/connections", { cache: "no-store" });
      const cb = await c.json();
      setConnections((Array.isArray(cb.connections) ? cb.connections : []).filter((x: any) => String(x.client_id) === clientId));
    } catch { /* ignore */ }
  };
  useEffect(() => { void load(); }, [clientId]);
  useEffect(() => {
    if (!autolog) return;
    const id = window.setInterval(() => { void loadAttempts(); }, 2500);
    return () => window.clearInterval(id);
  }, [autolog, clientId]);
  useEffect(() => { if (aFollowRef.current && aListRef.current) aListRef.current.scrollTop = aListRef.current.scrollHeight; }, [attempts]);
  useEffect(() => { if (kFollowRef.current && kListRef.current) kListRef.current.scrollTop = kListRef.current.scrollHeight; }, [connections]);
  const mkOnScroll = (elRef: any, followRef: any, resumeRef: any) => () => {
    const el = elRef.current; if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
    if (nearBottom) { if (resumeRef.current) window.clearTimeout(resumeRef.current); resumeRef.current = window.setTimeout(() => { followRef.current = true; }, 1500); }
    else { followRef.current = false; if (resumeRef.current) { window.clearTimeout(resumeRef.current); resumeRef.current = null; } }
  };
  const onAScroll = mkOnScroll(aListRef, aFollowRef, aResumeRef);
  const onKScroll = mkOnScroll(kListRef, kFollowRef, kResumeRef);
  const clearConnections = () => { setConnClearedAt(new Date().toISOString()); };
  const clearLog = async () => {
    setBusy(true); setMsg(null);
    try {
      await fetch(`/api/access/attempts/clear?client_id=${encodeURIComponent(clientId)}`, { method: "POST" });
      await loadAttempts();
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };

  const save = async (next?: { mode?: string; allow?: Dev[]; ban?: Dev[]; allow_ips?: string[]; ban_no_hwid?: boolean; conn_allow?: Dev[]; conn_ban?: Dev[]; conn_enforce?: boolean; conn_scope?: string; conn_instances?: string[] }) => {
    setBusy(true); setMsg(null);
    try {
      const body = { client_id: clientId, mode, allow, ban, allow_ips: allowIps, ban_no_hwid: banNoHwid, conn_allow: connAllow, conn_ban: connBan, conn_enforce: connEnforce, conn_scope: connScope, conn_instances: connInstances, ...next };
      const r = await fetch("/api/access/client", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
      const cc = (b.clients || {})[clientId] || {};
      setMode(cc.mode && cc.mode !== "inherit" ? cc.mode : "off");
      setAllow(Array.isArray(cc.allow) ? cc.allow : []);
      setBan(Array.isArray(cc.ban) ? cc.ban : []);
      setConnAllow(Array.isArray(cc.conn_allow) ? cc.conn_allow : []);
      setConnBan(Array.isArray(cc.conn_ban) ? cc.conn_ban : []);
      setAllowIps(Array.isArray(cc.allow_ips) ? cc.allow_ips : []);
      setBanNoHwid(!!cc.ban_no_hwid);
      setConnEnforce(!!cc.conn_enforce);
      setConnScope(cc.conn_scope === "selective" ? "selective" : "all");
      setConnInstances(Array.isArray(cc.conn_instances) ? cc.conn_instances : []);
      await load();
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const addIp = (ip: string) => { const v = (ip || "").trim(); if (!v) return; const nx = [...allowIps, v]; setAllowIps(nx); setNewIp(""); void save({ allow_ips: nx }); };
  const rmIp = (ip: string) => { const nx = allowIps.filter((x) => x !== ip); setAllowIps(nx); void save({ allow_ips: nx }); };
  const addConnAllow = (h: string) => { h = (h || "").trim(); if (!h) return; if (connAllow.some((d) => d.hwid.toLowerCase() === h.toLowerCase())) return; void save({ conn_allow: [...connAllow, { hwid: h, enabled: true }] }); };
  const addConnBan = (h: string) => { h = (h || "").trim(); if (!h) return; if (connBan.some((d) => d.hwid.toLowerCase() === h.toLowerCase())) return; void save({ conn_ban: [...connBan, { hwid: h, enabled: true }] }); };
  const rmConnAllow = (h: string) => void save({ conn_allow: connAllow.filter((d) => d.hwid !== h) });
  const rmConnBan = (h: string) => void save({ conn_ban: connBan.filter((d) => d.hwid !== h) });
  const toggleConnAllow = (h: string, en: boolean) => void save({ conn_allow: connAllow.map((d) => d.hwid === h ? { ...d, enabled: en } : d) });
  const toggleConnBan = (h: string, en: boolean) => void save({ conn_ban: connBan.map((d) => d.hwid === h ? { ...d, enabled: en } : d) });
  // Кросс-кнопка «добавить в противоположный список». title — полный текст (подсказка).
  const crossBtn = (hwid: string, kind: "allow" | "ban", target: "sub" | "conn", present: boolean, add: () => void) => {
    const key = `${clientId}|${hwid}|${kind}|${target}`;
    if (present) return null;
    if (hiddenCross.includes(key)) {
      return <button type="button" className="shrink-0 rounded border border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Показать кнопку добавления в противоположный список" onClick={() => unhideCross(key)}>⋯</button>;
    }
    const title = kind === "allow"
      ? (target === "sub" ? "Добавить в разрешённые устройства для получения подписки" : "Добавить в разрешённые устройства для подключения к инстансам")
      : (target === "sub" ? "Добавить в забаненные устройства для получения подписки" : "Добавить в забаненные устройства для подключения к инстансам");
    const label = (kind === "allow" ? "✅→" : "🚫→") + (target === "sub" ? "подписка" : "подключение");
    const cls = kind === "allow" ? "border-emerald-500/50 text-emerald-400 hover:bg-emerald-500/10" : "border-orange-500/50 text-orange-400 hover:bg-orange-500/10";
    return (
      <span className="inline-flex shrink-0 items-center">
        <button type="button" className={`rounded-l border px-1.5 py-1 text-[10px] ${cls}`} disabled={busy} title={title} onClick={add}>{label}</button>
        <button type="button" className="rounded-r border border-l-0 border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Скрыть эту кнопку (можно вернуть)" onClick={() => hideCross(key)}>×</button>
      </span>
    );
  };
  const toggleInstance = (room: string, on: boolean) => {
    const nx = on ? [...connInstances, room] : connInstances.filter((r) => r !== room);
    setConnInstances(nx); void save({ conn_instances: nx });
  };
  const allowIp = (ip: string) => addIp(ip); // из журнала — в per-client список этой подписки
  const addAllow = (h: string) => { h = h.trim(); if (!h) return; void save({ allow: [...allow, { hwid: h, enabled: true }] }); setNewAllow(""); };
  const addBan = (h: string) => { h = h.trim(); if (!h) return; void save({ ban: [...ban, { hwid: h, enabled: true }] }); setNewBan(""); };
  const rmAllow = (h: string) => void save({ allow: allow.filter((d) => d.hwid !== h) });
  const rmBan = (h: string) => void save({ ban: ban.filter((d) => d.hwid !== h) });
  const toggleAllow = (h: string, en: boolean) => void save({ allow: allow.map((d) => d.hwid === h ? { ...d, enabled: en } : d) });
  const toggleBan = (h: string, en: boolean) => void save({ ban: ban.map((d) => d.hwid === h ? { ...d, enabled: en } : d) });

  const devRow = (d: Dev, onToggle: ((en: boolean) => void) | null, onRemove: () => void, extra?: any) => (
    <div key={d.hwid} className="flex items-center gap-2 rounded border border-border px-2 py-1 text-[11px]">
      {onToggle && <input type="checkbox" title="вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => onToggle(e.target.checked)} />}
      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.label ? d.label + " · " : ""}{d.hwid}</span>
      {extra || null}
      <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={onRemove}>✕</button>
    </div>
  );

  // Синхронизация per-client списков с ГЛОБАЛЬНЫМИ (одной кнопкой). Объединение
  // (union): глобальные записи доливаются в списки подписки, ничего не удаляя.
  const hasHwid = (list: Dev[], h: string) => list.some((d) => (d.hwid || "").toLowerCase() === (h || "").toLowerCase());
  const mergeDev = (base: Dev[], add: Dev[]) => { const out = [...base]; for (const d of add || []) { if (d && d.hwid && !hasHwid(out, d.hwid)) out.push({ hwid: d.hwid, label: d.label, enabled: d.enabled !== false }); } return out; };
  const mergeIp = (base: string[], add: string[]) => Array.from(new Set([...(base || []), ...((add || []).filter(Boolean))]));
  const isSynced = () =>
    (glob.devices || []).every((d: Dev) => hasHwid(allow, d.hwid)) &&
    (glob.ban || []).every((d: Dev) => hasHwid(ban, d.hwid)) &&
    (glob.conn_devices || []).every((d: Dev) => hasHwid(connAllow, d.hwid)) &&
    (glob.conn_ban || []).every((d: Dev) => hasHwid(connBan, d.hwid)) &&
    (glob.allow_ips || []).every((ip: string) => (allowIps || []).includes(ip));
  const syncFromGlobal = () => {
    void save({
      allow: mergeDev(allow, glob.devices),
      ban: mergeDev(ban, glob.ban),
      conn_allow: mergeDev(connAllow, glob.conn_devices),
      conn_ban: mergeDev(connBan, glob.conn_ban),
      allow_ips: mergeIp(allowIps, glob.allow_ips),
      mode: mode === "off" ? "enforce" : mode,
    });
  };
  const setSyncHiddenPersist = (v: boolean) => { setSyncHidden(v); try { localStorage.setItem("olc-sync-hidden-" + clientId, v ? "1" : "0"); } catch { /* ignore */ } };
  const synced = isSynced();

  return (
    <Modal title={`Выборочный доступ · подписка ${clientId}`} onClose={onClose}>
      <div className="grid gap-3 p-4 text-sm">
        <div className="rounded-md border border-sky-500/30 bg-sky-500/5 p-3 text-xs text-muted-foreground">
          Это <b className="text-sky-400">выборочные</b> правила <b className="text-foreground">только для этой подписки и её инстансов</b>
          — независимо от других подписок. Действуют, когда глобальный контроль в общих настройках выключен.
          Идентификатор устройства (hwid) olcbox присылает при запросе подписки.
        </div>

        {syncHidden ? (
          <div className="flex justify-end">
            <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] text-muted-foreground hover:bg-muted" onClick={() => setSyncHiddenPersist(false)} title="Показать кнопку синхронизации с глобальными">⋯ синхронизация</button>
          </div>
        ) : (
          <div className={`flex items-center justify-between gap-2 rounded-md border px-3 py-2 ${synced ? "border-border bg-card/30" : "border-indigo-500/50 bg-indigo-500/10"}`}>
            <div className="min-w-0 text-[11px] text-muted-foreground">
              {synced ? "Списки этой подписки уже включают все глобальные записи." : "Скопировать все глобальные разрешённые/забаненные/IP в эту подписку (объединение, ничего не удаляя)."}
            </div>
            <div className="flex shrink-0 items-center gap-1">
              <button type="button" disabled={busy || synced}
                className={`rounded px-2 py-1 text-[11px] font-medium ${synced ? "cursor-not-allowed border border-border text-muted-foreground opacity-50" : "border border-indigo-500/60 bg-indigo-500/15 text-indigo-300 hover:bg-indigo-500/25"}`}
                onClick={syncFromGlobal}>Синхронизировать с глобальными</button>
              <button type="button" className="rounded border border-border px-1 py-1 text-[10px] text-muted-foreground hover:bg-muted" title="Скрыть (можно вернуть)" onClick={() => setSyncHiddenPersist(true)}>×</button>
            </div>
          </div>
        )}

        {/* ═══ СЕКЦИЯ A: доступ к получению подписки ═══ */}
        <div className="grid gap-3 rounded-md border border-border bg-card/30 p-3">
          <div className="text-sm font-semibold text-foreground">🎫 Кто может получить подписку</div>

          <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
            <label className="flex items-center gap-1">
              <input type="radio" name={`olc-cli-mode-${clientId}`} checked={mode === "off"} disabled={busy}
                onChange={() => { setMode("off"); void save({ mode: "off" }); }} />
              Выключено (пускать всех)
            </label>
            <label className="flex items-center gap-1">
              <input type="radio" name={`olc-cli-mode-${clientId}`} checked={mode === "monitor"} disabled={busy}
                onChange={() => { setMode("monitor"); void save({ mode: "monitor" }); }} />
              Наблюдение (лог, пускать)
            </label>
            <label className="flex items-center gap-1">
              <input type="radio" name={`olc-cli-mode-${clientId}`} checked={mode === "enforce"} disabled={busy}
                onChange={() => { setMode("enforce"); void save({ mode: "enforce" }); }} />
              Блокировать неизвестных
            </label>
          </div>

          <div className="grid gap-2 rounded-md border border-emerald-600/30 bg-emerald-500/5 p-2">
            <div className="text-xs font-semibold text-emerald-400">✅ Разрешённые устройства</div>
            {allow.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
            <div className="grid max-h-32 gap-1 overflow-y-auto">{allow.map((d) => devRow(d, (en) => toggleAllow(d.hwid, en), () => rmAllow(d.hwid), crossBtn(d.hwid, "allow", "conn", connAllow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnAllow(d.hwid))))}</div>
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (hwid)" value={newAllow} onChange={(e) => setNewAllow(e.target.value)} />
              <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-xs text-emerald-400 hover:bg-emerald-500/10" disabled={busy || !newAllow.trim()} onClick={() => addAllow(newAllow)}>Разрешить</button>
            </div>
            <details className="text-[11px]">
              <summary className="cursor-pointer text-muted-foreground">🌐 Разрешить по IP (для этой подписки)</summary>
              <div className="mt-2 grid gap-2">
                {allowIps.length > 0 && (
                  <div className="grid max-h-28 gap-1 overflow-y-auto">
                    {allowIps.map((ip) => (
                      <div key={ip} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1">
                        <span className="min-w-0 flex-1 truncate font-mono text-foreground">{ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmIp(ip)}>✕</button>
                      </div>
                    ))}
                  </div>
                )}
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="IP-адрес" value={newIp} onChange={(e) => setNewIp(e.target.value)} />
                  <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" disabled={busy || !newIp.trim()} onClick={() => addIp(newIp)}>Добавить IP</button>
                </div>
              </div>
            </details>
          </div>

          <div className="grid gap-2 rounded-md border border-red-500/30 bg-red-500/5 p-2">
            <div className="text-xs font-semibold text-red-400">🚫 Забаненные устройства (эта подписка)</div>
            {ban.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
            <div className="grid max-h-32 gap-1 overflow-y-auto">{ban.map((d) => devRow(d, (en) => toggleBan(d.hwid, en), () => rmBan(d.hwid), crossBtn(d.hwid, "ban", "conn", connBan.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnBan(d.hwid))))}</div>
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (забанить)" value={newBan} onChange={(e) => setNewBan(e.target.value)} />
              <button type="button" className="rounded-md border border-red-500/40 bg-red-500/10 px-3 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" disabled={busy || !newBan.trim()} onClick={() => addBan(newBan)}>Забанить</button>
            </div>
            <label className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <input type="checkbox" checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void save({ ban_no_hwid: e.target.checked }); }} />
              Блокировать запросы без hwid (Compatibility-режим olcbox)
            </label>
          </div>

          <div className="grid gap-2 rounded-md border border-border bg-background/60 p-2">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">📋 Журнал попыток получить подписку</div>
              <div className="flex items-center gap-2">
                {autolog
                  ? <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                  : <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearLog()}>Очистить</button>
              </div>
            </div>
            {attempts.length === 0 && <div className="text-[11px] text-muted-foreground">Пока нет.</div>}
            {attempts.length > 0 && (
            <div ref={aListRef} onScroll={onAScroll} className="grid max-h-40 gap-1 overflow-y-auto rounded border border-border bg-background p-2">
              {attempts.map((a, i) => {
                const hwid = String(a.hwid || "");
                const known = allow.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase());
                const banned = ban.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase());
                return (
                  <div key={hwid + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                    <div className="min-w-0">
                      <div className="truncate font-mono"><span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✗"}</span> {hwid || "(без hwid)"}{Number(a.count || 1) > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{a.count}</span>}</div>
                      <div className="truncate text-muted-foreground">{String(a.ip || "")} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                    </div>
                    {hwid && (
                      <div className="flex shrink-0 gap-1">
                        {!known && <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-emerald-400 hover:bg-emerald-500/10" disabled={busy} onClick={() => addAllow(hwid)}>Разрешить</button>}
                        {!banned && <button type="button" className="rounded border border-red-500/40 px-2 py-1 text-red-400 hover:bg-red-500/10" disabled={busy} onClick={() => addBan(hwid)}>Бан</button>}
                        {String(a.ip || "") && <button type="button" className="rounded border border-border px-2 py-1 text-muted-foreground hover:bg-muted" disabled={busy} title="Разрешить IP для этой подписки" onClick={() => addIp(String(a.ip))}>+IP</button>}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
            )}
          </div>
        </div>

        {/* ═══ СЕКЦИЯ B: доступ к подключению ═══ */}
        <div className="grid gap-3 rounded-md border border-border bg-card/30 p-3">
          <div className="text-sm font-semibold text-foreground">🔌 Кто может подключаться к инстансам</div>
          {globalEnforceConns ? (
            <div className="rounded border border-amber-500/40 bg-amber-500/10 px-2 py-2 text-[11px] text-amber-500">
              Действует <b>глобальный</b> контроль подключений (общие настройки). Выборочный по подписке недоступен,
              пока он включён; сохранённые здесь настройки вернутся после его выключения.
            </div>
          ) : (
            <>
              <label className="flex items-start gap-2 text-[11px] text-muted-foreground">
                <input type="checkbox" className="mt-0.5" checked={connEnforce} disabled={busy}
                  onChange={(e) => { setConnEnforce(e.target.checked); void save({ conn_enforce: e.target.checked }); }} />
                <span>Пускать к инстансам этой подписки только устройства из списка «Разрешённые для подключения» ниже.
                  Если список пуст — <b className="text-foreground">не пускает никого</b> (полная блокировка подключений).</span>
              </label>
              {connEnforce && (
                <div className="grid gap-2 pl-5">
                  <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">
                    <label className="flex items-center gap-1">
                      <input type="radio" name={`olc-conn-scope-${clientId}`} checked={connScope === "all"} disabled={busy}
                        onChange={() => { setConnScope("all"); void save({ conn_scope: "all" }); }} />
                      Все инстансы подписки
                    </label>
                    <label className="flex items-center gap-1">
                      <input type="radio" name={`olc-conn-scope-${clientId}`} checked={connScope === "selective"} disabled={busy}
                        onChange={() => { setConnScope("selective"); void save({ conn_scope: "selective" }); }} />
                      Только выбранные
                    </label>
                  </div>
                  {connScope === "selective" && (
                    <div className="grid gap-1">
                      {instances.length === 0 && <div className="text-[11px] text-muted-foreground">Инстансы не найдены.</div>}
                      {instances.map((it) => (
                        <label key={it.room_id} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1 text-[11px]">
                          <input type="checkbox" checked={connInstances.includes(it.room_id)} disabled={busy}
                            onChange={(e) => toggleInstance(it.room_id, e.target.checked)} />
                          <span className="min-w-0 flex-1 truncate">{it.name}</span>
                          <span className="shrink-0 font-mono text-muted-foreground">{it.room_id}</span>
                        </label>
                      ))}
                      <div className="text-[10px] text-muted-foreground">Контроль — только на отмеченных инстансах.</div>
                    </div>
                  )}
                </div>
              )}

              <div className="grid gap-2 rounded-md border border-sky-500/30 bg-sky-500/5 p-2">
                <div className="text-xs font-semibold text-sky-400">🔌✅ Разрешённые для ПОДКЛЮЧЕНИЯ (эта подписка)</div>
                <div className="text-[10px] text-muted-foreground">Отдельный список от «получения подписки». Кнопкой можно продублировать устройство в список подписки. <span className="text-amber-500">IP тут не фильтруется (на подключении виден только hwid).</span></div>
                {connAllow.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто{connEnforce ? " — при включённом контроле никто не подключится" : ""}.</div>}
                <div className="grid max-h-32 gap-1 overflow-y-auto">{connAllow.map((d) => devRow(d, (en) => toggleConnAllow(d.hwid, en), () => rmConnAllow(d.hwid), crossBtn(d.hwid, "allow", "sub", allow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addAllow(d.hwid))))}</div>
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (hwid)" value={newConnAllow} onChange={(e) => setNewConnAllow(e.target.value)} />
                  <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-xs text-sky-400 hover:bg-sky-500/10" disabled={busy || !newConnAllow.trim()} onClick={() => { addConnAllow(newConnAllow); setNewConnAllow(""); }}>Разрешить</button>
                </div>
              </div>

              <div className="grid gap-2 rounded-md border border-orange-500/30 bg-orange-500/5 p-2">
                <div className="text-xs font-semibold text-orange-400">🔌🚫 Забаненные для ПОДКЛЮЧЕНИЯ (эта подписка)</div>
                {connBan.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
                <div className="grid max-h-32 gap-1 overflow-y-auto">{connBan.map((d) => devRow(d, (en) => toggleConnBan(d.hwid, en), () => rmConnBan(d.hwid), crossBtn(d.hwid, "ban", "sub", ban.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addBan(d.hwid))))}</div>
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded border border-border bg-card px-2 text-xs text-foreground" placeholder="install-… (забанить подключение)" value={newConnBan} onChange={(e) => setNewConnBan(e.target.value)} />
                  <button type="button" className="rounded-md border border-orange-500/40 bg-orange-500/10 px-3 py-1 text-xs font-medium text-orange-400 hover:bg-orange-500/20" disabled={busy || !newConnBan.trim()} onClick={() => { addConnBan(newConnBan); setNewConnBan(""); }}>Забанить</button>
                </div>
              </div>
            </>
          )}
          <div className="grid gap-2 rounded-md border border-border bg-background/60 p-2">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">🔌 Журнал подключений (эта подписка)</div>
              <div className="flex items-center gap-2">
                {autolog
                  ? <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                  : <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={clearConnections}>Очистить</button>
              </div>
            </div>
            {(() => { const shown = connClearedAt ? connections.filter((c) => String(c.last || "") > connClearedAt) : connections; return (<>
            {shown.length === 0 && <div className="text-[11px] text-muted-foreground">Подключений пока нет.</div>}
            {shown.length > 0 && (
            <div ref={kListRef} onScroll={onKScroll} className="grid max-h-40 gap-1 overflow-y-auto rounded border border-border bg-background p-2">
              {shown.map((c, i) => {
                const dev = String(c.device || "");
                const known = connAllow.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                const banned = connBan.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                const loc = String(c.location_name || "");
                return (
                  <div key={dev + "|" + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                    <div className="min-w-0">
                      <div className="truncate font-mono">{dev} {known && <span className="text-sky-400">✓</span>}{Number(c.count || 1) > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{c.count}</span>}</div>
                      <div className="truncate text-muted-foreground">{loc ? <>инстанс: {loc} · </> : null}последнее: {String(c.last || "").slice(0, 19)}</div>
                    </div>
                    {dev && (
                      <div className="flex shrink-0 gap-1">
                        {!known && <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-sky-400 hover:bg-sky-500/10" disabled={busy} title="Разрешить для подключения" onClick={() => addConnAllow(dev)}>Разрешить</button>}
                        {!banned && <button type="button" className="rounded border border-orange-500/40 px-2 py-1 text-orange-400 hover:bg-orange-500/10" disabled={busy} title="Забанить для подключения" onClick={() => addConnBan(dev)}>Бан</button>}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
            )}
            </>); })()}
          </div>
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
if 'const [accessClient, setAccessClientRaw]' in t:
    print("[patch-client-access-ui] state already present")
elif state_anchor in t:
    inject = state_anchor + '''
  const [globalAccessEnabled, setGlobalAccessEnabled] = useState(false);
  const [accessClient, setAccessClientRaw] = useState<string | null>(() => { try { return localStorage.getItem("olc-modal-client-access-v1") || null; } catch { return null; } });
  const setAccessClient = (v: string | null) => { try { if (v) localStorage.setItem("olc-modal-client-access-v1", v); else localStorage.removeItem("olc-modal-client-access-v1"); } catch { /* ignore */ } setAccessClientRaw(v); };
  useEffect(() => {
    let stop = false;
    const load = async () => { try { const r = await fetch("/api/access/settings", { cache: "no-store" }); const b = await r.json(); if (!stop) setGlobalAccessEnabled(!!b.enabled); } catch { /* ignore */ } };
    void load();
    const id = window.setInterval(load, 5000);
    return () => { stop = true; window.clearInterval(id); };
  }, []);'''
    t = t.replace(state_anchor, inject, 1); changed = True
    print("[patch-client-access-ui] added accessClient state (persisted) + globalAccessEnabled")
else:
    print("[patch-client-access-ui] WARN: globalRandomizationEnabled state anchor not found")

# --- 3. Кнопка-шестерёнка после кнопки 🎲 ---
gear_anchor = '''                        🎲 {client.randomization?.enabled || globalRandomizationEnabled ? "ON" : "OFF"}
                      </button>'''
gear_add = gear_anchor + '''
                      <button
                        className="inline-flex h-8 items-center gap-1 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-40"
                        disabled={busy || globalAccessEnabled}
                        title={globalAccessEnabled ? "Для доступа к выборочным настройкам доступа по устройству отключите глобальный контроль доступа" : "Выборочный контроль доступа для этой подписки"}
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
render_add = '      {accessClient && !globalAccessEnabled && <ClientAccessModal clientId={accessClient} onClose={() => setAccessClient(null)} />}\n      {showSettings && ('
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
