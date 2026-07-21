#!/usr/bin/env bash
# Olc-cost-l UI (приёмка (г) сессии №16): модалка «Логи» клиента = ТРИ отдельных
# лога, каждый со своей системой автологов/умного скролла (как в FeatureLogsModal):
#   1) 🎫 Попытки подписки            — /api/access/attempts (фильтр по client_id)
#   2) 🔌 Попытки подключения к инст. — /api/access/connections (фильтр по client_id)
#   3) 🔌 Подключения (активны сейчас)— /api/state (device→инстанс по свежести peer_at)
# Каждая панель: autologi=Вкл → бейдж «Автообновление»; Выкл → «Обновить» + «Live».
# Умный скролл (useStickyLogScroll): просмотр старых строк НЕ утягивает вниз, новые
# строки НЕ двигают читаемое. Данные показываются НЕЗАВИСИМО от контроля доступа
# (эндпоинты отдают их всегда). Idempotent. Target: main.tsx. Run ПОСЛЕ client-qr-ui.
set -euo pipefail
MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-client-access-log] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False
def rep(old, new, tag):
    global t, changed
    if new in t:
        print(f"[client-access-log] {tag}: already applied"); return
    if old not in t:
        print(f"[client-access-log] WARN {tag}: anchor NOT FOUND"); return
    t = t.replace(old, new, 1); changed = True
    print(f"[client-access-log] {tag}: ok")

# --- 1. Компоненты ClientLogPanel + ClientAccessLogModal (перед function App) ---
comp = r'''function ClientLogPanel({ title, load, empty, autologi, liveKey, maxH, statusMode, hint }: { title: string; load: () => Promise<React.ReactNode[]>; empty: string; autologi: boolean; liveKey: string; maxH?: string; statusMode?: boolean; hint?: string }) {
  const { t } = usePanelLang();
  const [rows, setRows] = useState<React.ReactNode[]>([]);
  const [loading, setLoading] = useState(true);
  const [liveRaw, setLiveRaw] = useState(() => readStoredBool(liveKey, false));
  const setLive = (v: boolean | ((p: boolean) => boolean)) => setLiveRaw((prev) => { const nx = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v; writeStoredBool(liveKey, nx); return nx; });
  const live = autologi || liveRaw;
  const scroll = useStickyLogScroll<HTMLDivElement>([rows], true);
  const refresh = useCallback(async (showLoading: boolean) => {
    if (showLoading) setLoading(true);
    try { setRows(await load()); } catch { /* ignore */ } finally { setLoading(false); }
  }, [load]);
  useEffect(() => { void refresh(true); }, [refresh]);
  useEffect(() => {
    if (!live && !statusMode) return;
    const id = window.setInterval(() => void refresh(false), LOGS_LIVE_INTERVAL_MS);
    return () => window.clearInterval(id);
  }, [live, statusMode, refresh]);
  return (
    <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="text-xs font-semibold text-foreground">{title}</div>
        <div className="flex shrink-0 items-center gap-2">
          {statusMode ? (
            <span className="inline-flex items-center gap-1 rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[11px] text-emerald-600"><span className="text-emerald-400">●</span> живой статус</span>
          ) : autologi ? (
            <span className="inline-flex items-center rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[11px] text-emerald-600">Автообновление</span>
          ) : (
            <>
              <button type="button" className="inline-flex items-center rounded-md border border-border bg-background px-2 py-0.5 text-[11px] hover:bg-muted disabled:opacity-50" disabled={loading || live} onClick={() => void refresh(true)}>{t("refresh")}</button>
              <button type="button" className={"inline-flex items-center rounded-md border border-border px-2 py-0.5 text-[11px] hover:bg-muted " + (live ? "bg-primary text-primary-foreground" : "bg-background")} onClick={() => setLive((v) => !v)}>{live ? t("logsLiveOn") : t("logsLive")}</button>
            </>
          )}
        </div>
      </div>
      {hint && <div className="text-[11px] leading-snug text-muted-foreground">{hint}</div>}
      <LogScrollBox ref={scroll.ref} onScroll={scroll.onScroll} className={"overflow-y-auto rounded-md border border-border bg-black p-3 font-mono text-xs text-slate-100 " + (maxH || "max-h-52")}>
        {loading && rows.length === 0 ? (
          <div className="text-muted-foreground">{t("loadingLogs")}</div>
        ) : rows.length === 0 ? (
          <div className="text-muted-foreground">{empty}</div>
        ) : (
          rows
        )}
      </LogScrollBox>
    </div>
  );
}

function ClientAccessLogModal({ client, autologi, onClose }: { client: any; autologi: boolean; onClose: () => void }) {
  const { t } = usePanelLang();
  const cid = client.client_id;
  const loadAttempts = useCallback(async (): Promise<React.ReactNode[]> => {
    const b = await fetch("/api/access/attempts", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ attempts: [] }));
    return (b.attempts || []).filter((a: any) => a.client_id === cid).map((a: any, i: number) => (
      <div key={"a-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
        <span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✕"}</span>{" "}
        <span className="text-muted-foreground">{a.ts}</span>{"  "}{a.hwid || "—"} · {a.ip || "—"}{a.count > 1 ? ` ×${a.count}` : ""}{a.path ? ` · ${a.path}` : ""}
      </div>
    ));
  }, [cid]);
  const loadConns = useCallback(async (): Promise<React.ReactNode[]> => {
    const b = await fetch("/api/access/connections", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ connections: [] }));
    return (b.connections || []).filter((c: any) => c.client_id === cid).map((c: any, i: number) => (
      <div key={"c-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
        <span className="text-muted-foreground">{c.last}</span>{"  "}{c.device || "—"} <span className="text-muted-foreground">→</span> {c.location_name || c.room_id}{Number(c.count || 0) > 1 ? ` ×${c.count}` : ""}{Number(c.denied || 0) > 0 ? <span className="text-red-400" title="Отклонённые попытки подключения (бан / не в списке) — устройство НЕ подключилось"> 🚫 отклонено ×{c.denied}</span> : null}
      </div>
    ));
  }, [cid]);
  const loadActive = useCallback(async (): Promise<React.ReactNode[]> => {
    const d = await fetch("/api/state", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ clients: [] }));
    const lc = (d.clients || []).find((x: any) => x.client_id === cid);
    const byDev: Record<string, { inst: string; at: string }> = {};
    (lc?.locations || []).forEach((loc: any) => {
      const inst = loc.name || loc.room_id;
      const at = (loc.runtime && loc.runtime.peer_at) || "";
      ((loc.runtime && loc.runtime.peer_devices) || []).forEach((dev: string) => {
        if (!byDev[dev] || at > byDev[dev].at) byDev[dev] = { inst, at };
      });
    });
    return Object.keys(byDev).map((dev, i) => (
      <div key={"act-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
        <span className="text-emerald-400">●</span> {dev} <span className="text-muted-foreground">→</span> {byDev[dev].inst}
      </div>
    ));
  }, [cid]);
  return (
    <Modal title={t("logsClient", { id: cid })} onClose={onClose}>
      <div className="grid gap-3 p-5">
        <div className="text-xs text-muted-foreground">Данные по этому клиенту. Показываются независимо от того, включён ли контроль доступа.</div>
        <ClientLogPanel title="🎫 Попытки подписки" load={loadAttempts} empty="Попыток пока нет." autologi={autologi} liveKey={"olc-clog-att-" + cid} />
        <ClientLogPanel title="🔌 Попытки подключения к инстансам" load={loadConns} empty="Попыток пока нет." autologi={autologi} liveKey={"olc-clog-conn-" + cid} />
        <ClientLogPanel title="🔌 Подключения к инстансам (активны сейчас)" load={loadActive} empty="Нет активных подключений/туннелей." autologi={autologi} liveKey={"olc-clog-act-" + cid} maxH="max-h-40" statusMode hint="Отражает сессии, которые держит ядро. После реального отключения запись может исчезать с задержкой до ~1 минуты: ядро выдерживает окно на переподключение, чтобы кратковременный обрыв сети (напр. мобильная) не рвал туннель." />
      </div>
    </Modal>
  );
}

function App() {'''
rep("function App() {", comp, "ClientAccessLogModal + ClientLogPanel components")

# --- 2. openClientLogs: только открыть модалку (без лишнего fetch инстанс-логов) ---
rep(
'''  const openClientLogs = async (client: ClientState) => {
    setClientLogs([]);
    setNotice("");
    setClientLogTarget(client);
    await refreshClientLogs(client);
  };''',
'''  const openClientLogs = (client: ClientState) => {
    setNotice("");
    setClientLogTarget(client);
  };''',
"openClientLogs simplified")

# --- 3. Убрать старый App-поллинг логов клиента (панели опрашивают себя сами) ---
rep(
'''  useEffect(() => {
    if (!clientLogTarget || !clientLogsLive) return;
    const id = window.setInterval(() => {
      refreshClientLogs(clientLogTarget).catch((err) =>
        setNotice(err instanceof Error ? err.message : String(err)),
      );
    }, LOGS_LIVE_INTERVAL_MS);
    return () => window.clearInterval(id);
  }, [clientLogTarget, clientLogsLive, refreshClientLogs]);

''',
'  // client-log poll removed: панели ClientLogPanel опрашивают себя сами\n\n',
"remove old client-log App poll")

# --- 4. Заменить всю модалку логов клиента на новый компонент ---
old_modal = '''      {clientLogTarget && (
        <Modal title={t("logsClient", { id: clientLogTarget.client_id })} onClose={() => setClientLogTarget(null)}>
          <div className="p-5">
            <LogScrollBox
              ref={clientLogScroll.ref}
              onScroll={clientLogScroll.onScroll}
              className="max-h-[520px] overflow-y-auto rounded-md border border-border bg-black p-3 font-mono text-xs text-slate-100"
            >
              {clientLogs.length === 0 ? (
                <div className="text-muted-foreground">{t("loadingLogs")}</div>
              ) : (
                clientLogs.map((group) => (
                  <div key={`${group.location.room_id}-${group.location.transport}`} className="mb-5 last:mb-0">
                    <div className="mb-2 text-[11px] uppercase text-muted-foreground">
                      {group.location.name || t("defaultLocationName")} · {group.location.transport} · {group.location.runtime.status}
                    </div>
                    {group.error ? (
                      <div className="text-muted-foreground">{t("logsUnavailableDetail", { error: group.error })}</div>
                    ) : group.lines.length === 0 ? (
                      <div className="text-muted-foreground">Логов пока нет</div>
                    ) : (
                      group.lines.map((line, index) => (
                        <div key={`${line.time}-${index}`} className="whitespace-pre-wrap break-words">
                          {logsVerbose ? (
                            <>
                              <span className={line.stream === "stderr" ? "text-destructive" : "text-primary"}>
                                {line.stream}
                              </span>{" "}
                              <span className="text-muted-foreground">{line.time}</span> {line.line}
                            </>
                          ) : (
                            line.line
                          )}
                        </div>
                      ))
                    )}
                  </div>
                ))
              )}
            </LogScrollBox>

            <div className="mt-5 flex items-center justify-between gap-2">
              <label className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                <input type="checkbox" checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
                {t("logsVerbose")}
              </label>
              {autologi ? (
                <span className="inline-flex items-center rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-1 text-xs text-emerald-600">Автообновление</span>
              ) : (
                <>
                  <button
                    className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-50"
                    disabled={clientLogsLive}
                    onClick={() => openClientLogs(clientLogTarget)}
                  >
                    {t("refresh")}
                  </button>
                  <button
                    className={`h-9 rounded-md border border-border px-3 text-sm hover:bg-muted/80 ${
                      clientLogsLive ? "bg-primary text-primary-foreground" : "bg-muted"
                    }`}
                    onClick={() => setClientLogsLive((value) => !value)}
                  >
                    {clientLogsLive ? t("logsLiveOn") : t("logsLive")}
                  </button>
                </>
              )}
            </div>
          </div>
        </Modal>
      )}'''
new_modal = '''      {clientLogTarget && (
        <ClientAccessLogModal client={clientLogTarget} autologi={autologi} onClose={() => setClientLogTarget(null)} />
      )}'''
rep(old_modal, new_modal, "client log modal -> ClientAccessLogModal")

if changed:
    f.write_text(t)
print("[patch-client-access-log] done")
PY
