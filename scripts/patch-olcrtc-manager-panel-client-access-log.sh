#!/usr/bin/env bash
# Olc-cost-l UI (Этап 5B эпика): перепрофилировать кнопку «Логи» клиента —
# вместо стопки логов инстансов показывать ПЛОСКИЙ лог попыток подписки/доступа
# ИМЕННО этого клиента (из /api/access/attempts + /api/access/connections).
# Idempotent. Target: main.tsx. Run ПОСЛЕ client-qr-ui.
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

# 0. Убрать чекбокс «Показать подробно» из логов клиента (первое вхождение = модалка клиента)
rep(
'''              <label className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                <input type="checkbox" checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
                {t("logsVerbose")}
              </label>''',
'''              <span className="text-xs text-muted-foreground">Попытки доступа этого клиента</span>''',
"remove verbose checkbox (client modal)")

# 1. Состояние clientAccessLog
rep(
"  const [clientLogs, setClientLogs] = useState<ClientLogGroup[]>([]);",
"  const [clientLogs, setClientLogs] = useState<ClientLogGroup[]>([]);\n  const [clientAccessLog, setClientAccessLog] = useState<{ attempts: any[]; conns: any[] }>({ attempts: [], conns: [] });",
"clientAccessLog state")

# 2. refreshClientLogs → грузит попытки подписки + подключения этого клиента
rep(
'''  const refreshClientLogs = useCallback(async (client: ClientState) => {
    const groups = await Promise.all(
      client.locations.map(async (location) => {
        try {
          const res = await request(logsURL(client.client_id, location), { cache: "no-store" });
          const body = (await res.json()) as { logs: LogLine[] };
          return { location, lines: body.logs ?? [] };
        } catch (err) {
          return { location, lines: [], error: err instanceof Error ? err.message : String(err) };
        }
      }),
    );
    setClientLogs(groups);
  }, []);''',
'''  const refreshClientLogs = useCallback(async (client: ClientState) => {
    try {
      const [ar, cr] = await Promise.all([
        fetch("/api/access/attempts", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ attempts: [] })),
        fetch("/api/access/connections", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ connections: [] })),
      ]);
      const attempts = (ar.attempts || []).filter((a: any) => a.client_id === client.client_id);
      const conns = (cr.connections || []).filter((c: any) => c.client_id === client.client_id);
      setClientAccessLog({ attempts, conns });
    } catch {
      setClientAccessLog({ attempts: [], conns: [] });
    }
    setClientLogs([]);
  }, []);''',
"refreshClientLogs -> access log")

# 3. Рендер: плоский список попыток подписки + подключений
rep(
'''              {clientLogs.length === 0 ? (
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
              )}''',
'''              {clientAccessLog.attempts.length === 0 && clientAccessLog.conns.length === 0 ? (
                <div className="text-muted-foreground">Попыток пока не зафиксировано.</div>
              ) : (
                <>
                  <div className="mb-1 text-[11px] uppercase text-muted-foreground">🎫 Попытки подписки</div>
                  {clientAccessLog.attempts.length === 0 ? (
                    <div className="mb-3 text-muted-foreground">Пусто.</div>
                  ) : (
                    clientAccessLog.attempts.map((a: any, index: number) => (
                      <div key={`a-${index}`} className="whitespace-pre-wrap break-words">
                        <span className={a.allowed ? "text-emerald-400" : "text-red-400"}>{a.allowed ? "✓" : "✕"}</span>{" "}
                        <span className="text-muted-foreground">{a.ts}</span> {a.hwid || "—"} · {a.ip || "—"}{a.count > 1 ? ` ×${a.count}` : ""}{a.path ? ` · ${a.path}` : ""}
                      </div>
                    ))
                  )}
                  <div className="mb-1 mt-4 text-[11px] uppercase text-muted-foreground">🔌 Подключения к инстансам</div>
                  {clientAccessLog.conns.length === 0 ? (
                    <div className="text-muted-foreground">Пусто.</div>
                  ) : (
                    clientAccessLog.conns.map((c: any, index: number) => (
                      <div key={`c-${index}`} className="whitespace-pre-wrap break-words">
                        <span className="text-muted-foreground">{c.last}</span> {c.device || "—"} · {c.location_name || c.room_id}{c.count > 1 ? ` ×${c.count}` : ""}
                      </div>
                    ))
                  )}
                </>
              )}''',
"client logs render -> flat access log")

if changed:
    f.write_text(t)
print("[patch-client-access-log] done")
PY
