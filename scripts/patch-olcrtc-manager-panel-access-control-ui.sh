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
  const [devices, setDevices] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [ban, setBan] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [banNoHwid, setBanNoHwid] = useState(false);
  const [enforceConns, setEnforceConns] = useState(false);
  const [allowedIps, setAllowedIps] = useState<string[]>([]);
  const [newIp, setNewIp] = useState("");
  const [attempts, setAttempts] = useState<Array<Record<string, any>>>([]);
  const [connections, setConnections] = useState<Array<Record<string, any>>>([]);
  const [autolog, setAutolog] = useState(true);
  const [newHwid, setNewHwid] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const listRef = useRef<HTMLDivElement | null>(null);
  const followRef = useRef(true);
  const resumeRef = useRef<number | null>(null);
  const connListRef = useRef<HTMLDivElement | null>(null);
  const connFollowRef = useRef(true);
  const connResumeRef = useRef<number | null>(null);
  const [connClearedAt, setConnClearedAt] = useState<string>("");

  const loadSettings = async () => {
    try {
      const s = await fetch("/api/access/settings", { cache: "no-store" });
      const sb = await s.json();
      setEnabled(!!sb.enabled);
      setMode(sb.mode === "enforce" ? "enforce" : "monitor");
      setDevices(Array.isArray(sb.devices) ? sb.devices : []);
      setBan(Array.isArray(sb.ban) ? sb.ban : []);
      setBanNoHwid(!!sb.ban_no_hwid);
      setEnforceConns(!!sb.enforce_connections);
      setAllowedIps(Array.isArray(sb.allowed_ips) ? sb.allowed_ips : []);
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
  useEffect(() => {
    if (connFollowRef.current && connListRef.current) {
      connListRef.current.scrollTop = connListRef.current.scrollHeight;
    }
  }, [connections]);

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
  const onConnScroll = () => {
    const el = connListRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
    if (nearBottom) {
      if (connResumeRef.current) window.clearTimeout(connResumeRef.current);
      connResumeRef.current = window.setTimeout(() => { connFollowRef.current = true; }, 1500);
    } else {
      connFollowRef.current = false;
      if (connResumeRef.current) { window.clearTimeout(connResumeRef.current); connResumeRef.current = null; }
    }
  };
  const clearConnections = () => { setConnClearedAt(new Date().toISOString()); };

  const saveSettings = async (next: { enabled?: boolean; mode?: string; ban?: any[]; ban_no_hwid?: boolean; enforce_connections?: boolean }) => {
    setBusy(true); setMsg(null);
    try {
      const body = { enabled, mode, devices, ban, ban_no_hwid: banNoHwid, enforce_connections: enforceConns, ...next };
      const res = await fetch("/api/access/settings", {
        method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
      });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : "monitor");
      setDevices(Array.isArray(b.devices) ? b.devices : []);
      setBan(Array.isArray(b.ban) ? b.ban : []);
      setBanNoHwid(!!b.ban_no_hwid);
      setEnforceConns(!!b.enforce_connections);
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const banDevice = (hwid: string) => { const h = (hwid || "").trim(); if (!h) return; const nx = [...ban, { hwid: h, enabled: true }]; setBan(nx); void saveSettings({ ban: nx }); };
  const removeBan = (hwid: string) => { const nx = ban.filter((d) => d.hwid !== hwid); setBan(nx); void saveSettings({ ban: nx }); };
  const toggleBan = (hwid: string, en: boolean) => { const nx = ban.map((d) => d.hwid === hwid ? { ...d, enabled: en } : d); setBan(nx); void saveSettings({ ban: nx }); };
  const allow = async (hwid: string) => {
    if (!hwid) return;
    setBusy(true); setMsg(null);
    try {
      const res = await fetch("/api/access/allow", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ hwid }) });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setDevices(Array.isArray(b.devices) ? b.devices : []);
      setBan(Array.isArray(b.ban) ? b.ban : ban);
      setNewHwid("");
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const remove = async (hwid: string) => {
    setBusy(true); setMsg(null);
    try {
      const res = await fetch("/api/access/remove", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ hwid }) });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setDevices(Array.isArray(b.devices) ? b.devices : []);
      setBan(Array.isArray(b.ban) ? b.ban : ban);
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
  const setDevice = async (hwid: string, patch: { label?: string; enabled?: boolean }) => {
    setBusy(true); setMsg(null);
    try {
      const res = await fetch("/api/access/device", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ hwid, ...patch }) });
      const b = await res.json();
      if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
      setDevices(Array.isArray(b.devices) ? b.devices : []);
      setBan(Array.isArray(b.ban) ? b.ban : ban);
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  // IP-allowlist: backend уже энфорсит allowed_ips (olcAccessAllowed), UI лишь
  // управляет списком через те же /api/access/{allow,remove} с телом {ip}.
  const allowIp = async (ip: string) => {
    const v = (ip || "").trim(); if (!v) return;
    setBusy(true);
    try {
      const res = await fetch("/api/access/allow", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ip: v }) });
      const b = await res.json();
      setAllowedIps(Array.isArray(b.allowed_ips) ? b.allowed_ips : []);
      setNewIp("");
    } catch { /* ignore */ } finally { setBusy(false); }
  };
  const removeIp = async (ip: string) => {
    setBusy(true);
    try {
      const res = await fetch("/api/access/remove", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ip }) });
      const b = await res.json();
      setAllowedIps(Array.isArray(b.allowed_ips) ? b.allowed_ips : []);
    } catch { /* ignore */ } finally { setBusy(false); }
  };
  const isKnown = (hwid: string) => devices.some((d) => (d.hwid || "").toLowerCase() === hwid.toLowerCase());

  return (
    <section className="grid gap-4 rounded-md border border-border bg-background p-4">
      <div>
        <div className="text-sm font-semibold text-foreground">🔐 Контроль доступа по устройству</div>
        <div className="mt-1 text-xs text-muted-foreground">
          Белый список устройств по идентификатору <span className="font-mono">hwid</span>, который olcbox
          присылает при запросе подписки. Разрешённые устройства получают доступ, чужие — блокируются и
          попадают в журнал. Все данные хранятся только на этом сервере.
        </div>
      </div>
      <label className="flex items-center gap-2 text-sm font-medium text-foreground">
        <input type="checkbox" checked={enabled} disabled={busy}
          onChange={(e) => { setEnabled(e.target.checked); void saveSettings({ enabled: e.target.checked }); }} />
        Включить контроль доступа
      </label>

      {enabled && (
        <>
          {/* ── БЛОК 1: два независимых уровня защиты ── */}
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Уровни защиты</div>
            <div className="grid gap-1">
              <div className="text-[11px] font-medium text-foreground">1. Доступ к подписке <span className="font-normal text-muted-foreground">— кто может ПОЛУЧИТЬ ссылку-подписку</span></div>
              <div className="flex flex-wrap gap-3 pl-3 text-xs text-muted-foreground">
                <label className="flex items-center gap-1">
                  <input type="radio" name="olc-ac-mode" checked={mode === "monitor"} disabled={busy}
                    onChange={() => { setMode("monitor"); void saveSettings({ mode: "monitor" }); }} />
                  Наблюдение (пускать всех, вести журнал)
                </label>
                <label className="flex items-center gap-1">
                  <input type="radio" name="olc-ac-mode" checked={mode === "enforce"} disabled={busy}
                    onChange={() => { setMode("enforce"); void saveSettings({ mode: "enforce" }); }} />
                  Блокировать неизвестных
                </label>
              </div>
            </div>
            <div className="grid gap-1 border-t border-border pt-2">
              <div className="text-[11px] font-medium text-foreground">2. Доступ к подключению <span className="font-normal text-muted-foreground">— кто может ПОДКЛЮЧИТЬСЯ к инстансам (даже с валидной ссылкой)</span></div>
              <label className="flex items-start gap-2 pl-3 text-xs text-muted-foreground">
                <input type="checkbox" className="mt-0.5" checked={enforceConns} disabled={busy}
                  onChange={(e) => { setEnforceConns(e.target.checked); void saveSettings({ enforce_connections: e.target.checked }); }} />
                <span>
                  Блокировать неизвестные устройства на подключении (закрывает «слитый инстанс»).
                  <span className="text-amber-500"> ⚠️ Проверьте на своём устройстве перед тем, как полагаться —
                  использует тот же список разрешённых. При пустом списке подключение НЕ блокируется.</span>
                </span>
              </label>
            </div>
          </div>

          {/* ── БЛОК 2: разрешённые устройства ── */}
          <div className="grid gap-2 rounded-md border border-emerald-600/30 bg-emerald-500/5 p-3">
            <div className="text-xs font-semibold text-emerald-400">✅ Разрешённые устройства</div>
            {devices.length === 0 && <div className="text-xs text-muted-foreground">Пока пусто. Добавьте hwid вручную или кнопкой «Разрешить» из журнала/подключений ниже.</div>}
            {devices.length > 0 && (
              <div className="grid max-h-40 gap-1 overflow-y-auto">
                {devices.map((d) => (
                  <div key={d.hwid} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1 text-xs">
                    <input type="checkbox" title="Вкл/выкл доступ" checked={d.enabled !== false} disabled={busy}
                      onChange={(e) => void setDevice(d.hwid, { enabled: e.target.checked })} />
                    <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
                      placeholder="имя" defaultValue={d.label || ""}
                      onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) void setDevice(d.hwid, { label: e.target.value }); }} />
                    <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>
                    <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => void remove(d.hwid)}>✕</button>
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
                placeholder="install-… (hwid устройства)" value={newHwid} onChange={(e) => setNewHwid(e.target.value)} />
              <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={busy || !newHwid.trim()} onClick={() => void allow(newHwid.trim())}>Добавить</button>
            </div>
            <details className="text-[11px]">
              <summary className="cursor-pointer text-muted-foreground">🌐 Разрешить по IP (без hwid — напр. свой сервер/скрипт)</summary>
              <div className="mt-2 grid gap-2">
                {allowedIps.length > 0 && (
                  <div className="grid max-h-32 gap-1 overflow-y-auto">
                    {allowedIps.map((ip) => (
                      <div key={ip} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1">
                        <span className="min-w-0 flex-1 truncate font-mono text-foreground">{ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => void removeIp(ip)}>✕</button>
                      </div>
                    ))}
                  </div>
                )}
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
                    placeholder="IP-адрес (напр. 203.0.113.7)" value={newIp} onChange={(e) => setNewIp(e.target.value)} />
                  <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" disabled={busy || !newIp.trim()} onClick={() => void allowIp(newIp.trim())}>Добавить IP</button>
                </div>
              </div>
            </details>
          </div>

          {/* ── БЛОК 3: забаненные устройства ── */}
          <div className="grid gap-2 rounded-md border border-red-500/30 bg-red-500/5 p-3">
            <div className="text-xs font-semibold text-red-400">🚫 Забаненные устройства (глобально)</div>
            <div className="text-[11px] text-muted-foreground">Жёсткий блок — перекрывает разрешение, даже если устройство в белом списке.</div>
            {ban.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
            {ban.length > 0 && (
              <div className="grid max-h-32 gap-1 overflow-y-auto">
                {ban.map((d) => (
                  <div key={d.hwid} className="flex items-center gap-2 rounded border border-red-500/30 bg-background px-2 py-1 text-xs">
                    <input type="checkbox" title="Вкл/выкл бан" checked={d.enabled !== false} disabled={busy} onChange={(e) => toggleBan(d.hwid, e.target.checked)} />
                    <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : "text-red-300"}`}>{d.hwid}</span>
                    <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => removeBan(d.hwid)}>✕</button>
                  </div>
                ))}
              </div>
            )}
            <label className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <input type="checkbox" checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void saveSettings({ ban_no_hwid: e.target.checked }); }} />
              Блокировать запросы без hwid (Compatibility-режим olcbox — «поймать всё устройство»)
            </label>
          </div>

          {/* ── БЛОК 4: журнал попыток подписки ── */}
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">📋 Журнал попыток (подписка)</div>
              <div className="flex items-center gap-2">
                {autolog ? (
                  <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                ) : (
                  <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>
                )}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearAttempts()}>Очистить</button>
              </div>
            </div>
            {attempts.length === 0 && <div className="text-xs text-muted-foreground">Попыток пока не зафиксировано.</div>}
            {attempts.length > 0 && (
              <div ref={listRef} onScroll={onScroll} className="grid max-h-56 gap-1 overflow-y-auto rounded border border-border bg-background p-2">
                {attempts.map((a, i) => {
                  const hwid = String(a.hwid || "");
                  const known = isKnown(hwid);
                  const count = Number(a.count || 1);
                  return (
                    <div key={hwid + "|" + String(a.client_id) + "|" + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                      <div className="min-w-0">
                        <div className="truncate font-mono">
                          <span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✗"}</span> {hwid || "(без hwid)"}
                          {count > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{count}</span>}
                        </div>
                        <div className="truncate text-muted-foreground">{String(a.ip || "")} · подписка: {String(a.client_id || "—")} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                      </div>
                      {hwid && (
                        <div className="flex shrink-0 gap-1">
                          {!known && <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-emerald-400 hover:bg-emerald-500/10" disabled={busy} onClick={() => void allow(hwid)}>Разрешить</button>}
                          {!ban.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase()) && <button type="button" className="rounded border border-red-500/40 px-2 py-1 text-red-400 hover:bg-red-500/10" disabled={busy} onClick={() => banDevice(hwid)}>Бан</button>}
                          {String(a.ip || "") && !allowedIps.includes(String(a.ip)) && <button type="button" className="rounded border border-border px-2 py-1 text-muted-foreground hover:bg-muted" disabled={busy} title="Разрешить этот IP" onClick={() => void allowIp(String(a.ip))}>+IP</button>}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* ── БЛОК 5: подключения к инстансам (с привязкой клиент/инстанс) ── */}
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="flex items-center justify-between">
              <div className="text-xs font-semibold text-foreground">🔌 Подключения к инстансам</div>
              <div className="flex items-center gap-2">
                {autolog ? (
                  <span className="rounded-full border border-emerald-600/50 bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400">● автологи</span>
                ) : (
                  <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void loadAttempts()}>Обновить</button>
                )}
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={clearConnections}>Очистить</button>
              </div>
            </div>
            <div className="text-[11px] text-muted-foreground">Устройства (device), реально подключавшиеся к инстансам — тот же идентификатор, что hwid подписки. Показывает, к какой подписке и инстансу шло подключение.</div>
            {(() => { const shown = connClearedAt ? connections.filter((c) => String(c.last || "") > connClearedAt) : connections; return (<>
            {shown.length === 0 && <div className="text-xs text-muted-foreground">Подключений пока не зафиксировано.</div>}
            {shown.length > 0 && (
              <div ref={connListRef} onScroll={onConnScroll} className="grid max-h-56 gap-1 overflow-y-auto rounded border border-border bg-background p-2">
                {shown.map((c, i) => {
                  const dev = String(c.device || "");
                  const known = isKnown(dev);
                  const count = Number(c.count || 1);
                  const cid = String(c.client_id || "");
                  const loc = String(c.location_name || "");
                  const banned = ban.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                  return (
                    <div key={dev + "|" + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                      <div className="min-w-0">
                        <div className="truncate font-mono">{dev} {known && <span className="text-emerald-400">✓</span>}{count > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{count}</span>}</div>
                        <div className="truncate text-muted-foreground">{(cid || loc) ? <>подписка: {cid || "—"}{loc ? <> · инстанс: {loc}</> : null} · </> : null}последнее: {String(c.last || "").slice(0, 19)}</div>
                      </div>
                      {dev && (
                        <div className="flex shrink-0 gap-1">
                          {!known && <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-emerald-400 hover:bg-emerald-500/10" disabled={busy} onClick={() => void allow(dev)}>Разрешить</button>}
                          {!banned && <button type="button" className="rounded border border-red-500/40 px-2 py-1 text-red-400 hover:bg-red-500/10" disabled={busy} onClick={() => banDevice(dev)}>Бан</button>}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
            </>); })()}
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
