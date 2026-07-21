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
  const [connDevices, setConnDevices] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [connBan, setConnBan] = useState<Array<{ hwid: string; label?: string; enabled: boolean }>>([]);
  const [newConnDev, setNewConnDev] = useState("");
  const [newConnBan, setNewConnBan] = useState("");
  const [hiddenCross, setHiddenCross] = useState<string[]>(() => { try { return JSON.parse(localStorage.getItem("olc-cross-hidden-g-v1") || "[]"); } catch { return []; } });
  const hideCross = (k: string) => { const nx = Array.from(new Set([...hiddenCross, k])); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-g-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const unhideCross = (k: string) => { const nx = hiddenCross.filter((x) => x !== k); setHiddenCross(nx); try { localStorage.setItem("olc-cross-hidden-g-v1", JSON.stringify(nx)); } catch { /* ignore */ } };
  const [allowedIps, setAllowedIps] = useState<Array<{ ip: string; enabled: boolean }>>([]);
  const normIps = (v: any) => (Array.isArray(v) ? v : []).map((x: any) => (typeof x === "string" ? { ip: x, enabled: true } : { ip: String(x?.ip || ""), enabled: x?.enabled !== false })).filter((x: any) => x.ip);
  const [newIp, setNewIp] = useState("");
  const [banIps, setBanIps] = useState<Array<{ ip: string; enabled: boolean }>>([]);
  const [newBanIp, setNewBanIp] = useState("");
  // Мини-модалка подтверждения (конфликт бан↔разрешено).
  const [confirmA, setConfirmA] = useState<null | { text: string; ok: string; cancel: string; okCls: "red" | "emerald"; run: () => void }>(null);
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
  const [connClearedAt, setConnClearedAt] = useState<string>(() => { try { return localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });

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
      setConnDevices(Array.isArray(sb.conn_devices) ? sb.conn_devices : []);
      setConnBan(Array.isArray(sb.conn_ban) ? sb.conn_ban : []);
      setAllowedIps(normIps(sb.allowed_ips));
      setBanIps(normIps(sb.ban_ips));
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
  const clearConnections = async () => {
    setBusy(true);
    try { await fetch("/api/access/connections?clear=1", { cache: "no-store" }); } catch { /* ignore */ }
    const ts = new Date().toISOString(); setConnClearedAt(ts); try { localStorage.setItem("olc-conn-cleared-global", ts); } catch { /* ignore */ }
    await loadAttempts(); setBusy(false);
  };

  const saveSettings = async (next: { enabled?: boolean; mode?: string; devices?: any[]; ban?: any[]; ban_no_hwid?: boolean; enforce_connections?: boolean; conn_devices?: any[]; conn_ban?: any[]; allowed_ips?: any[]; ban_ips?: any[] }) => {
    setBusy(true); setMsg(null);
    try {
      // ЧАСТИЧНОЕ сохранение: шлём ТОЛЬКО изменённые поля (backend мержит).
      // Полное тело со stale state затирало параллельные изменения.
      const body = { ...next };
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
      setConnDevices(Array.isArray(b.conn_devices) ? b.conn_devices : []);
      setConnBan(Array.isArray(b.conn_ban) ? b.conn_ban : []);
      if (Array.isArray(b.allowed_ips)) setAllowedIps(normIps(b.allowed_ips));
      if (Array.isArray(b.ban_ips)) setBanIps(normIps(b.ban_ips));
      try { window.dispatchEvent(new CustomEvent("olc-access-saved", { detail: { enabled: !!b.enabled } })); } catch { /* ignore */ }
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  // ── Конфликт бан↔разрешено: НИКОГДА не держать hwid/IP в обоих списках.
  // Добавление при наличии в противоположном списке → мини-модалка; подтверждение
  // = атомарный перенос (один saveSettings).
  const inL = (list: Array<{ hwid: string }>, h: string) => (list || []).some((d) => (d.hwid || "").toLowerCase() === (h || "").toLowerCase());
  const dropH = (list: Array<any>, h: string) => (list || []).filter((d) => (d.hwid || "").toLowerCase() !== (h || "").toLowerCase());
  const ipIn = (list: any[], ip: string) => (list || []).some((x: any) => x.ip === ip);
  const dropIp = (list: any[], ip: string) => (list || []).filter((x: any) => x.ip !== ip);
  const setConnDevice = (hwid: string, patch: { enabled?: boolean }) => { const nx = connDevices.map((d) => d.hwid === hwid ? { ...d, ...patch } : d); setConnDevices(nx); void saveSettings({ conn_devices: nx }); };
  const addConnDevice = (hwid: string) => {
    const h = (hwid || "").trim(); if (!h || inL(connDevices, h)) return;
    if (inL(connBan, h)) {
      setConfirmA({ text: `Устройство ${h} забанено для ПОДКЛЮЧЕНИЯ. Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => void saveSettings({ conn_ban: dropH(connBan, h), conn_devices: [...connDevices, { hwid: h, enabled: true }] }) });
      return;
    }
    void saveSettings({ conn_devices: [...connDevices, { hwid: h, enabled: true }] });
  };
  const rmConnDevice = (hwid: string) => { const nx = connDevices.filter((d) => d.hwid !== hwid); setConnDevices(nx); void saveSettings({ conn_devices: nx }); };
  const addConnBan = (hwid: string) => {
    const h = (hwid || "").trim(); if (!h || inL(connBan, h)) return;
    if (inL(connDevices, h)) {
      setConfirmA({ text: `Устройство ${h} в списке разрешённых для ПОДКЛЮЧЕНИЯ. Оно будет удалено из разрешённых и забанено.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => void saveSettings({ conn_devices: dropH(connDevices, h), conn_ban: [...connBan, { hwid: h, enabled: true }] }) });
      return;
    }
    void saveSettings({ conn_ban: [...connBan, { hwid: h, enabled: true }] });
  };
  const rmConnBan = (hwid: string) => { const nx = connBan.filter((d) => d.hwid !== hwid); setConnBan(nx); void saveSettings({ conn_ban: nx }); };
  const toggleConnBan = (hwid: string, en: boolean) => { const nx = connBan.map((d) => d.hwid === hwid ? { ...d, enabled: en } : d); setConnBan(nx); void saveSettings({ conn_ban: nx }); };
  const crossBtn = (hwid: string, kind: "allow" | "ban", target: "sub" | "conn", present: boolean, add: () => void) => {
    const key = `${hwid}|${kind}|${target}`;
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
  const banDevice = (hwid: string) => {
    const h = (hwid || "").trim(); if (!h || inL(ban, h)) return;
    if (inL(devices, h)) {
      setConfirmA({ text: `Устройство ${h} в списке разрешённых (подписка). Оно будет удалено из разрешённых и забанено.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => void saveSettings({ devices: dropH(devices, h), ban: [...ban, { hwid: h, enabled: true }] }) });
      return;
    }
    void saveSettings({ ban: [...ban, { hwid: h, enabled: true }] });
  };
  const removeBan = (hwid: string) => { const nx = ban.filter((d) => d.hwid !== hwid); setBan(nx); void saveSettings({ ban: nx }); };
  const toggleBan = (hwid: string, en: boolean) => { const nx = ban.map((d) => d.hwid === hwid ? { ...d, enabled: en } : d); setBan(nx); void saveSettings({ ban: nx }); };
  const allow = async (hwid: string) => {
    const h = (hwid || "").trim(); if (!h || inL(devices, h)) return;
    if (inL(ban, h)) {
      setConfirmA({ text: `Устройство ${h} забанено (подписка). Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { setNewHwid(""); void saveSettings({ ban: dropH(ban, h), devices: [...devices, { hwid: h, enabled: true }] }); } });
      return;
    }
    setNewHwid("");
    await saveSettings({ devices: [...devices, { hwid: h, enabled: true }] });
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
    const v = (ip || "").trim(); if (!v || ipIn(allowedIps, v)) return;
    if (ipIn(banIps, v)) {
      setConfirmA({ text: `IP ${v} забанен (подписка). Разбанить его и добавить в разрешённые?`, ok: "Разбанить", cancel: "Нет", okCls: "emerald", run: () => { setNewIp(""); void saveSettings({ ban_ips: dropIp(banIps, v), allowed_ips: [...allowedIps, { ip: v, enabled: true }] }); } });
      return;
    }
    setNewIp("");
    await saveSettings({ allowed_ips: [...allowedIps, { ip: v, enabled: true }] });
  };
  const banIp = (ip: string) => {
    const v = (ip || "").trim(); if (!v || ipIn(banIps, v)) return;
    if (ipIn(allowedIps, v)) {
      setConfirmA({ text: `IP ${v} в списке разрешённых (подписка). Он будет удалён из разрешённых и забанен.`, ok: "Бан", cancel: "Отмена", okCls: "red", run: () => { setNewBanIp(""); void saveSettings({ allowed_ips: dropIp(allowedIps, v), ban_ips: [...banIps, { ip: v, enabled: true }] }); } });
      return;
    }
    setNewBanIp("");
    void saveSettings({ ban_ips: [...banIps, { ip: v, enabled: true }] });
  };
  const rmBanIp = (ip: string) => { const nx = banIps.filter((x) => x.ip !== ip); setBanIps(nx); void saveSettings({ ban_ips: nx }); };
  const toggleBanIp = (ip: string, en: boolean) => { const nx = banIps.map((x) => (x.ip === ip ? { ...x, enabled: en } : x)); setBanIps(nx); void saveSettings({ ban_ips: nx }); };
  const toggleIp = (ip: string, en: boolean) => { const nx = allowedIps.map((x) => (x.ip === ip ? { ...x, enabled: en } : x)); setAllowedIps(nx); void saveSettings({ allowed_ips: nx }); };
  const removeIp = async (ip: string) => {
    setBusy(true);
    try {
      const res = await fetch("/api/access/remove", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ip }) });
      const b = await res.json();
      setAllowedIps(normIps(b.allowed_ips));
    } catch { /* ignore */ } finally { setBusy(false); }
  };
  const isKnown = (hwid: string) => devices.some((d) => (d.hwid || "").toLowerCase() === hwid.toLowerCase());
  // Режимы секций: «Выключено» затемняет и блокирует ТОЛЬКО свою область разрешённых.
  const subOff = mode !== "enforce";
  const connOff = !enforceConns;
  const dimCls = (off: boolean) => (off ? " pointer-events-none opacity-40 select-none" : "");

  return (
    <section className="grid gap-4 rounded-md border border-border bg-background p-4">
      <div>
        <div className="text-sm font-semibold text-foreground">🔐 Глобальный контроль доступа по устройству</div>
        <div className="mt-1 text-xs text-muted-foreground">
          Действует на <b className="text-foreground">все подписки</b>. Белый список устройств по <span className="font-mono">hwid</span>,
          который olcbox присылает при запросе подписки. Пока он включён — выборочные настройки в ⚙ у клиентов недоступны.
          Все данные хранятся только на этом сервере.
        </div>
      </div>
      <label className="flex items-center gap-2 text-sm font-medium text-foreground">
        <input type="checkbox" checked={enabled} disabled={busy}
          onChange={(e) => { setEnabled(e.target.checked); void saveSettings({ enabled: e.target.checked }); }} />
        Включить контроль доступа
      </label>

      {enabled && (
        <>
          {/* ── БЛОК 1: доступ к подписке (режим) ── */}
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="text-xs font-semibold text-foreground">🎫 Доступ к подписке <span className="font-normal text-muted-foreground">— кто может ПОЛУЧИТЬ ссылку-подписку (списки ниже)</span></div>
            <div className="flex flex-wrap gap-2 text-xs">
              <button type="button" disabled={busy}
                className={subOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (subOff) return; setMode("monitor"); void saveSettings({ mode: "monitor" }); }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              <button type="button" disabled={busy}
                className={!subOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (!subOff) return; setMode("enforce"); void saveSettings({ mode: "enforce" }); }}>
                Блокировать неизвестных (+логирование)
              </button>
            </div>
            <div className="text-[10px] leading-snug text-muted-foreground">Журнал и бан-лист действуют в ОБОИХ режимах. «Блокировать неизвестных» дополнительно пускает только устройства/IP из «Разрешённых».</div>
          </div>

          {/* ── БЛОК 2: разрешённые устройства ── */}
          <div className={"grid gap-2 rounded-md border border-emerald-600/30 bg-emerald-500/5 p-3" + dimCls(subOff)}
            title={subOff ? "Режим «Выключено»: списки разрешённых не действуют и недоступны — включите «Блокировать неизвестных»" : undefined}>
            <div className="text-xs font-semibold text-emerald-400">✅ Разрешённые устройства (получение подписки){subOff ? " — не действуют в режиме «Выключено»" : ""}</div>
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
                    {crossBtn(d.hwid, "allow", "conn", connDevices.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnDevice(d.hwid))}
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
                <div className="text-[11px] leading-snug text-amber-500/90">⚠️ IP-список действует НЕЗАВИСИМО от списка устройств: запрос с включённого IP получает подписку, даже если его устройство выключено или отсутствует в списке. Чтобы IP перестал действовать — снимите с него галочку (или удалите).</div>
                {allowedIps.length > 0 && (
                  <div className="grid max-h-32 gap-1 overflow-y-auto">
                    {allowedIps.map((x) => (
                      <div key={x.ip} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1">
                        <input type="checkbox" checked={x.enabled} disabled={busy} title={x.enabled ? "IP активен: пропускает подписку" : "IP выключен: не действует"} onChange={(e) => toggleIp(x.ip, e.target.checked)} />
                        <span className={"min-w-0 flex-1 truncate font-mono " + (x.enabled ? "text-foreground" : "text-muted-foreground line-through opacity-60")}>{x.ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => void removeIp(x.ip)}>✕</button>
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
            <div className="text-xs font-semibold text-red-400">🚫 Забаненные устройства (получение подписки)</div>
            <div className="text-[11px] text-muted-foreground">Жёсткий блок — действует ВСЕГДА, в обоих режимах (и в «Выключено»).</div>
            {ban.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
            {ban.length > 0 && (
              <div className="grid max-h-32 gap-1 overflow-y-auto">
                {ban.map((d) => (
                  <div key={d.hwid} className="flex items-center gap-2 rounded border border-red-500/30 bg-background px-2 py-1 text-xs">
                    <input type="checkbox" title="Вкл/выкл бан" checked={d.enabled !== false} disabled={busy} onChange={(e) => toggleBan(d.hwid, e.target.checked)} />
                    <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : "text-red-300"}`}>{d.hwid}</span>
                    {crossBtn(d.hwid, "ban", "conn", connBan.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnBan(d.hwid))}
                    <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => removeBan(d.hwid)}>✕</button>
                  </div>
                ))}
              </div>
            )}
            <details className="text-[11px]">
              <summary className="cursor-pointer text-muted-foreground">🌐🚫 Забаненные IP (получение подписки)</summary>
              <div className="mt-2 grid gap-2">
                <div className="text-[11px] leading-snug text-amber-500/90">⚠️ Бан по IP действует ВСЕГДА — в обоих режимах (и в «Выключено»). Запрос подписки с забаненного IP блокируется независимо от устройства.</div>
                {banIps.length > 0 && (
                  <div className="grid max-h-32 gap-1 overflow-y-auto">
                    {banIps.map((x) => (
                      <div key={x.ip} className="flex items-center gap-2 rounded border border-red-500/30 bg-background px-2 py-1">
                        <input type="checkbox" checked={x.enabled} disabled={busy} title={x.enabled ? "Бан IP активен" : "Бан IP выключен: не действует"} onChange={(e) => toggleBanIp(x.ip, e.target.checked)} />
                        <span className={"min-w-0 flex-1 truncate font-mono " + (x.enabled ? "text-red-300" : "text-muted-foreground line-through opacity-60")}>{x.ip}</span>
                        <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmBanIp(x.ip)}>✕</button>
                      </div>
                    ))}
                  </div>
                )}
                {banIps.length === 0 && <div className="text-[11px] text-muted-foreground">Пусто.</div>}
                <div className="flex gap-2">
                  <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary"
                    placeholder="IP-адрес (забанить)" value={newBanIp} onChange={(e) => setNewBanIp(e.target.value)} />
                  <button type="button" className="rounded-md border border-red-500/40 bg-red-500/10 px-2 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" disabled={busy || !newBanIp.trim()} onClick={() => banIp(newBanIp)}>Забанить IP</button>
                </div>
              </div>
            </details>
            <label className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <input type="checkbox" checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void saveSettings({ ban_no_hwid: e.target.checked }); }} />
              Блокировать запросы без hwid (Compatibility-режим olcbox) — действует в обоих режимах
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
                  const aip = String(a.ip || "");
                  const ipAllowed = ipIn(allowedIps, aip);
                  const ipBanned = ipIn(banIps, aip);
                  return (
                    <div key={hwid + "|" + String(a.client_id) + "|" + i} className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]">
                      <div className="min-w-0">
                        <div className="truncate font-mono">
                          <span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✗"}</span> {hwid || "(без hwid)"}
                          {count > 1 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{count}</span>}
                        </div>
                        <div className="truncate text-muted-foreground">{aip} · подписка: {String(a.client_id || "—")} · {String(a.ua || "")} · {String(a.ts || "").slice(0, 19)}</div>
                      </div>
                      {hwid && (
                        <div className="flex shrink-0 gap-1">
                          {!known && (subOff
                            ? <button type="button" className="cursor-not-allowed rounded border border-border px-2 py-1 text-muted-foreground opacity-40" disabled title="Режим «Выключено»: разрешённые не действуют. Доступно в «Блокировать неизвестных»">Разрешить</button>
                            : <button type="button" className="rounded border border-emerald-600/50 px-2 py-1 text-emerald-400 hover:bg-emerald-500/10" disabled={busy} onClick={() => void allow(hwid)}>Разрешить</button>)}
                          {!ban.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase()) && <button type="button" className="rounded border border-red-500/40 px-2 py-1 text-red-400 hover:bg-red-500/10" disabled={busy} onClick={() => banDevice(hwid)}>Бан</button>}
                          {aip && (subOff
                            ? (!ipBanned && <button type="button" className="rounded border border-red-500/50 bg-red-500/10 px-2 py-1 text-red-400 hover:bg-red-500/20" disabled={busy} title="Режим «Выключено»: IP можно только ЗАБАНИТЬ (разрешённые IP не действуют)" onClick={() => banIp(aip)}>+IP</button>)
                            : <span className="inline-flex shrink-0">
                                {!ipAllowed && <button type="button" className={"border border-emerald-600/50 px-1.5 py-1 text-emerald-400 hover:bg-emerald-500/10 " + (ipBanned ? "rounded" : "rounded-l")} disabled={busy} title="Разрешить этот IP" onClick={() => void allowIp(aip)}>+IP</button>}
                                {!ipBanned && <button type="button" className={"border border-red-500/50 px-1.5 py-1 text-red-400 hover:bg-red-500/10 " + (ipAllowed ? "rounded" : "rounded-r border-l-0")} disabled={busy} title="Забанить этот IP" onClick={() => banIp(aip)}>🚫</button>}
                              </span>)}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* ── БЛОК 4b: контроль ПОДКЛЮЧЕНИЯ (отдельные списки) ── */}
          <div className="grid gap-2 rounded-md border border-sky-500/40 bg-sky-500/5 p-3">
            <div className="text-xs font-semibold text-sky-400">🔌 Доступ к подключению <span className="font-normal text-muted-foreground">— кто может ПОДКЛЮЧИТЬСЯ к инстансам (даже с валидной ссылкой)</span></div>
            <div className="flex flex-wrap gap-2 text-xs">
              <button type="button" disabled={busy}
                className={connOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (connOff) return; setEnforceConns(false); void saveSettings({ enforce_connections: false }); }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              <button type="button" disabled={busy}
                className={!connOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (!connOff) return; setEnforceConns(true); void saveSettings({ enforce_connections: true }); }}>
                Блокировать неизвестных (+логирование)
              </button>
            </div>
            <div className="text-[10px] leading-snug text-muted-foreground">«Блокировать неизвестных»: на подключении пускаются только устройства из списка ниже (закрывает «слитый инстанс»). Если список пуст — <b className="text-foreground">не пускает никого</b>. Журнал и бан-лист действуют в ОБОИХ режимах.<span className="text-amber-500"> ⚠️ Проверьте на своём устройстве.</span></div>
            <div className={"grid gap-2" + dimCls(connOff)} title={connOff ? "Режим «Выключено»: список разрешённых не действует и недоступен — включите «Блокировать неизвестных»" : undefined}>
              <div className="text-xs font-semibold text-sky-400">🔌 Разрешённые устройства (подключение к инстансам){connOff ? " — не действуют в режиме «Выключено»" : ""}</div>
              <div className="text-[11px] text-muted-foreground">ОТДЕЛЬНЫЙ список от «получения подписки». <span className="text-amber-500">IP-фильтра здесь нет: на подключении виден только hwid устройства, не IP — IP-контроль работает только в разделе «получение подписки».</span></div>
              {connDevices.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
              {connDevices.length > 0 && (
                <div className="grid max-h-40 gap-1 overflow-y-auto">
                  {connDevices.map((d) => (
                    <div key={d.hwid} className="flex items-center gap-2 rounded border border-sky-500/30 bg-background px-2 py-1 text-xs">
                      <input type="checkbox" title="Вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => setConnDevice(d.hwid, { enabled: e.target.checked })} />
                      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>
                      {crossBtn(d.hwid, "allow", "sub", devices.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => void allow(d.hwid))}
                      <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmConnDevice(d.hwid)}>✕</button>
                    </div>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary" placeholder="install-… (hwid)" value={newConnDev} onChange={(e) => setNewConnDev(e.target.value)} />
                <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-xs text-sky-400 hover:bg-sky-500/10" disabled={busy || !newConnDev.trim()} onClick={() => { addConnDevice(newConnDev.trim()); setNewConnDev(""); }}>Разрешить</button>
              </div>
            </div>
          </div>

          {/* ── БЛОК 4c: бан подключения ── */}
          <div className="grid gap-2 rounded-md border border-orange-500/30 bg-orange-500/5 p-3">
            <div className="text-xs font-semibold text-orange-400">🔌🚫 Забаненные устройства (подключение к инстансам)</div>
            <div className="text-[10px] text-amber-500/90">Бан действует ВСЕГДА — в обоих режимах (и в «Выключено»).</div>
            {connBan.length === 0 && <div className="text-xs text-muted-foreground">Пусто.</div>}
            {connBan.length > 0 && (
              <div className="grid max-h-32 gap-1 overflow-y-auto">
                {connBan.map((d) => (
                  <div key={d.hwid} className="flex items-center gap-2 rounded border border-orange-500/30 bg-background px-2 py-1 text-xs">
                    <input type="checkbox" title="Вкл/выкл бан" checked={d.enabled !== false} disabled={busy} onChange={(e) => toggleConnBan(d.hwid, e.target.checked)} />
                    <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : "text-orange-300"}`}>{d.hwid}</span>
                    {crossBtn(d.hwid, "ban", "sub", ban.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => banDevice(d.hwid))}
                    <button type="button" className="shrink-0 text-red-400 hover:text-red-300" disabled={busy} onClick={() => rmConnBan(d.hwid)}>✕</button>
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input className="h-8 flex-1 rounded-md border border-border bg-card px-2 text-xs text-foreground outline-none focus:border-primary" placeholder="install-… (забанить подключение)" value={newConnBan} onChange={(e) => setNewConnBan(e.target.value)} />
              <button type="button" className="rounded-md border border-orange-500/40 bg-orange-500/10 px-3 py-1 text-xs font-medium text-orange-400 hover:bg-orange-500/20" disabled={busy || !newConnBan.trim()} onClick={() => { addConnBan(newConnBan.trim()); setNewConnBan(""); }}>Забанить</button>
            </div>
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
                <button type="button" className="rounded border border-border px-2 py-0.5 text-[10px] hover:bg-muted" disabled={busy} onClick={() => void clearConnections()}>Очистить</button>
              </div>
            </div>
            <div className="text-[11px] text-muted-foreground">Устройства (device), реально подключавшиеся к инстансам — тот же идентификатор, что hwid подписки. Показывает, к какой подписке и инстансу шло подключение.</div>
            {(() => { const shown = connClearedAt ? connections.filter((c) => String(c.last || "") > connClearedAt) : connections;
            // Группировка по девайсу: одна запись на устройство, внутри — развернуть по подпискам/инстансам.
            const gmap: Record<string, any[]> = {};
            for (const c of shown) { const k = String(c.device || ""); (gmap[k] = gmap[k] || []).push(c); }
            const groups = Object.entries(gmap).map(([gdev, rows]) => ({
              dev: gdev,
              rows: rows.slice().sort((a: any, b: any) => (String(a.last || "") < String(b.last || "") ? -1 : 1)),
              count: rows.reduce((s: number, r: any) => s + Number(r.count || 0), 0),
              denied: rows.reduce((s: number, r: any) => s + Number(r.denied || 0), 0),
              kicked: rows.reduce((s: number, r: any) => s + Number(r.kicked || 0), 0),
              last: rows.reduce((m: string, r: any) => (String(r.last || "") > m ? String(r.last || "") : m), ""),
            })).sort((a, b) => (a.last < b.last ? -1 : 1));
            return (<>
            {groups.length === 0 && <div className="text-xs text-muted-foreground">Подключений пока не зафиксировано.</div>}
            {groups.length > 0 && (
              <div ref={connListRef} onScroll={onConnScroll} className="grid max-h-56 gap-1 overflow-y-auto rounded border border-border bg-background p-2">
                {groups.map((g) => {
                  const dev = g.dev;
                  const known = connDevices.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                  const banned = connBan.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());
                  return (
                    <details key={dev} className="rounded border border-border px-2 py-1 text-[11px]">
                      <summary className="flex cursor-pointer list-none items-center justify-between gap-2">
                        <div className="min-w-0">
                          <div className="truncate font-mono">▸ {dev || "—"} {known && <span className="text-sky-400">✓</span>}{g.count > 0 && <span className="ml-1 rounded bg-muted px-1 text-muted-foreground">×{g.count}</span>}{g.denied > 0 && <span className="ml-1 rounded border border-red-500/40 bg-red-500/10 px-1 text-red-400" title="Отклонённые попытки подключения (бан / не в списке) — устройство НЕ подключилось, это ретраи клиента">🚫 отклонено ×{g.denied}</span>}{g.kicked > 0 && <span className="ml-1 rounded border border-orange-500/40 bg-orange-500/10 px-1 text-orange-400" title="Живая сессия сброшена ядром по бану (ban-watcher): устройство было подключено и его отключило">⛔ сброшен ×{g.kicked}</span>}</div>
                          <div className="truncate text-muted-foreground">инстансов: {g.rows.length} · последнее: {String(g.last).slice(0, 19)}{g.count === 0 && g.denied > 0 ? " · только отклонённые попытки" : ""}</div>
                        </div>
                        {dev && (
                          <div className="flex shrink-0 gap-1" onClick={(e) => { e.preventDefault(); e.stopPropagation(); }}>
                            {!known && (connOff
                              ? <button type="button" className="cursor-not-allowed rounded border border-border px-2 py-1 text-muted-foreground opacity-40" disabled title="Режим «Выключено»: разрешённые не действуют. Доступно в «Блокировать неизвестных»">Разрешить</button>
                              : <button type="button" className="rounded border border-sky-500/50 px-2 py-1 text-sky-400 hover:bg-sky-500/10" disabled={busy} title="Разрешить для ПОДКЛЮЧЕНИЯ" onClick={() => addConnDevice(dev)}>Разрешить</button>)}
                            {!banned && <button type="button" className="rounded border border-orange-500/40 px-2 py-1 text-orange-400 hover:bg-orange-500/10" disabled={busy} title="Забанить для ПОДКЛЮЧЕНИЯ (действует в обоих режимах)" onClick={() => addConnBan(dev)}>Бан</button>}
                          </div>
                        )}
                      </summary>
                      <div className="mt-1 grid gap-0.5 border-t border-border pt-1">
                        {g.rows.map((c: any, i: number) => (
                          <div key={i} className="flex items-center justify-between gap-2 pl-3 text-[11px]">
                            <span className="min-w-0 truncate">→ {String(c.client_id || "—")}{c.location_name ? <> · {String(c.location_name)}</> : null}</span>
                            <span className="shrink-0 text-muted-foreground">{Number(c.count || 0) > 0 ? `×${c.count}` : ""}{Number(c.denied || 0) > 0 ? <span className="text-red-400"> 🚫×{c.denied}</span> : null}{Number(c.kicked || 0) > 0 ? <span className="text-orange-400"> ⛔×{c.kicked}</span> : null} · {String(c.last || "").slice(0, 19)}</span>
                          </div>
                        ))}
                      </div>
                    </details>
                  );
                })}
              </div>
            )}
            </>); })()}
          </div>
        </>
      )}
      {msg && <div className="text-xs text-red-500 whitespace-pre-wrap">{msg}</div>}
      {confirmA && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4" onClick={() => setConfirmA(null)}>
          <div className="w-full max-w-sm rounded-lg border border-border bg-card p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <div className="text-sm leading-snug text-foreground">{confirmA.text}</div>
            <div className="mt-3 flex justify-end gap-2">
              <button type="button" className="rounded border border-border px-3 py-1 text-xs hover:bg-muted" onClick={() => setConfirmA(null)}>{confirmA.cancel}</button>
              <button type="button"
                className={confirmA.okCls === "red" ? "rounded border border-red-500/50 bg-red-500/10 px-3 py-1 text-xs font-medium text-red-400 hover:bg-red-500/20" : "rounded border border-emerald-600/50 bg-emerald-500/10 px-3 py-1 text-xs font-medium text-emerald-400 hover:bg-emerald-500/20"}
                onClick={() => { const r = confirmA.run; setConfirmA(null); r(); }}>{confirmA.ok}</button>
            </div>
          </div>
        </div>
      )}
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
