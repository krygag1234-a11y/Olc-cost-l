#!/usr/bin/env bash
# Olc-cost-l frontend: заменить нерабочую кнопку «OlcBox» (падала на
# navigator.clipboard.writeText — clipboard недоступен на http) на кнопку «Info»
# (цветная обводка) на КАЖДОМ инстансе. Info открывает модалку с полной сводкой по
# инстансу: статус/аптайм/память/рестарты, активные подключения сейчас, журнал по
# устройствам (принято/отклонено/кик, first/last) с очисткой, рандомизация ключей
# (ориг + рандомизированный: тип1 статичный / тип2 посекундный live), учёт автологов.
# Плюс: (1) чинит copyOlcBoxLink/copySubscription (безопасное копирование с
# fallback execCommand); (2) добавляет модалку в F5-автовосстановление + чинит
# автовосстановление Qr-модалки клиента (subQr). Idempotent. Target: main.tsx.
# Run ПОСЛЕ modal-memory и client-qr-ui.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-instance-info] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-instance-info] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-instance-info] {label}: ok")
    else:
        print(f"[patch-instance-info] WARN {label}: anchor not found")

# --- 1. Безопасное копирование (fallback), общий хелпер ---
helper_guard = 'function olcSafeCopy('
helper_anchor = 'function subscriptionURL(clientID: string, subscriptionPath?: string) {'
helper_block = '''async function olcSafeCopy(text: string): Promise<void> {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
  } catch { /* fall through to legacy copy */ }
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.position = "fixed";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand("copy"); } finally { document.body.removeChild(ta); }
}

'''
if helper_guard in t:
    print("[patch-instance-info] olcSafeCopy: already applied")
elif helper_anchor in t:
    t = t.replace(helper_anchor, helper_block + helper_anchor, 1); changed = True
    print("[patch-instance-info] olcSafeCopy: ok")
else:
    print("[patch-instance-info] WARN olcSafeCopy: anchor not found")

# --- 2. Fix copyOlcBoxLink / copySubscription: use olcSafeCopy ---
repl(
    '''      if (!uri) throw new Error("OlcBox ссылка не найдена");
      await navigator.clipboard.writeText(uri);''',
    '''      if (!uri) throw new Error("OlcBox ссылка не найдена");
      await olcSafeCopy(uri);''',
    "fix copyOlcBoxLink",
    guard="await olcSafeCopy(uri);",
)
repl(
    '      await navigator.clipboard.writeText(subscriptionURL(clientID, currentSubscriptionPath));',
    '      await olcSafeCopy(subscriptionURL(clientID, currentSubscriptionPath));',
    "fix copySubscription",
    guard="await olcSafeCopy(subscriptionURL(clientID, currentSubscriptionPath));",
)

# --- 2b. Fix ClientQrModal copy (crashes on http, no fallback) + copy-feedback ---
repl(
    '  const copy = (s: string) => { if (s) void navigator.clipboard.writeText(s); };',
    '''  const [copiedKey, setCopiedKey] = useState("");
  const copy = (s: string, key: string) => {
    if (!s) return;
    void olcSafeCopy(s);
    setCopiedKey(key);
    window.setTimeout(() => setCopiedKey((k) => (k === key ? "" : k)), 1500);
  };''',
    "fix ClientQrModal copy + feedback state",
    guard="const [copiedKey, setCopiedKey] = useState",
)

# --- 2c. QR copy button: press animation + «Скопировано» ---
repl(
    '<button type="button" className="h-8 rounded-md border border-border bg-muted px-3 text-xs hover:bg-muted/80 disabled:opacity-50" disabled={!url} onClick={() => copy(url)}>Копировать</button>',
    '<button type="button" className={"h-8 rounded-md border px-3 text-xs transition-transform active:scale-95 disabled:opacity-50 " + (copiedKey === k ? "border-emerald-500/60 bg-emerald-500/15 text-emerald-500 font-medium" : "border-border bg-muted hover:bg-muted/80")} disabled={!url} onClick={() => copy(url, k)}>{copiedKey === k ? "✓ Скопировано" : "Копировать"}</button>',
    "QR copy button feedback",
    guard="{copiedKey === k ? \"✓ Скопировано\" : \"Копировать\"}",
)

# --- 3. Компонент InstanceInfoModal (перед function App) ---
comp_guard = 'function InstanceInfoModal('
comp_anchor = 'function App()'
comp_block = r'''// ============================================================================
// Olc-cost-l: Info-модалка отдельного инстанса. Самодостаточна: опрашивает
// /api/state (активные пиры/аптайм/память), /api/instances/info (ключи+трафик),
// /api/access/connections (журнал по устройствам этого инстанса). Учитывает
// автологи: при autologi=on журнал обновляется автоматически, иначе — по кнопке
// «Обновить». Живой статус (активные пиры) опрашивается всегда пока модалка
// открыта. Для тип2 рандомизации ключей рандомизированный ключ тикает раз в сек.
// ============================================================================
function olcFmtBytes(n?: number): string {
  if (!n || n <= 0) return "0 B";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0; let v = n;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(i === 0 ? 0 : 2)} ${u[i]}`;
}
function olcFmtUptime(started?: string): string {
  if (!started) return "—";
  const ms = Date.now() - new Date(started).getTime();
  if (isNaN(ms) || ms < 0) return "—";
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}д ${h}ч ${m}м`;
  if (h > 0) return `${h}ч ${m}м`;
  if (m > 0) return `${m}м ${s % 60}с`;
  return `${s}с`;
}

function InstanceInfoModal({ clientID, roomID, name, autologi, onClose }: { clientID: string; roomID: string; name?: string; autologi: boolean; onClose: () => void }) {
  const [runtime, setRuntime] = useState<any>(null);
  const [peers, setPeers] = useState<{ count: number; devices: string[] }>({ count: 0, devices: [] });
  const [info, setInfo] = useState<any>(null);
  const [conns, setConns] = useState<any[]>([]);
  const [msg, setMsg] = useState("");
  const [showOrig, setShowOrig] = useState(false);
  const [showRand, setShowRand] = useState(false);

  const loadStatus = async () => {
    try {
      const r = await fetch("/api/state", { cache: "no-store" });
      const b = await r.json();
      const c = (b.clients || []).find((x: any) => x.client_id === clientID);
      const loc = c?.locations?.find((l: any) => l.room_id === roomID);
      if (loc) {
        setRuntime(loc.runtime || null);
        const rt = loc.runtime || {};
        setPeers({ count: typeof rt.peer_count === "number" ? rt.peer_count : (Array.isArray(rt.peer_devices) ? rt.peer_devices.length : 0), devices: Array.isArray(rt.peer_devices) ? rt.peer_devices : [] });
      }
    } catch { /* ignore */ }
  };
  const loadInfo = async () => {
    try {
      const r = await fetch(`/api/instances/info?client_id=${encodeURIComponent(clientID)}&room_id=${encodeURIComponent(roomID)}`, { cache: "no-store" });
      if (r.ok) setInfo(await r.json());
    } catch { /* ignore */ }
  };
  const loadConns = async () => {
    try {
      const r = await fetch("/api/access/connections", { cache: "no-store" });
      const b = await r.json();
      setConns((Array.isArray(b.connections) ? b.connections : []).filter((rec: any) => rec.room_id === roomID));
    } catch { /* ignore */ }
  };
  const clearJournal = async () => {
    if (!window.confirm("Очистить журнал подключений этой подписки (все инстансы клиента)?")) return;
    try {
      await fetch(`/api/access/connections?clear=1&client_id=${encodeURIComponent(clientID)}`, { cache: "no-store" });
      setMsg("Журнал очищен");
      await loadConns();
    } catch { setMsg("Ошибка очистки"); }
  };

  // Живой статус (пиры/рантайм) — всегда пока модалка открыта.
  useEffect(() => {
    void loadStatus();
    const id = window.setInterval(() => { void loadStatus(); }, 2000);
    return () => window.clearInterval(id);
  }, [clientID, roomID]);

  // Ключи/трафик: тип2 (dynamic) — раз в секунду, иначе раз в 5с.
  const dynamic = !!info?.key_rand?.dynamic;
  useEffect(() => {
    void loadInfo();
    const id = window.setInterval(() => { void loadInfo(); }, dynamic ? 1000 : 5000);
    return () => window.clearInterval(id);
  }, [clientID, roomID, dynamic]);

  // Журнал устройств: автологи — авто-обновление; иначе — по кнопке.
  useEffect(() => {
    void loadConns();
    if (!autologi) return;
    const id = window.setInterval(() => { void loadConns(); }, 4000);
    return () => window.clearInterval(id);
  }, [clientID, roomID, autologi]);

  const kr = info?.key_rand;
  const traffic = info?.traffic;
  const mask = (s?: string) => (s ? (s.length > 16 ? s.slice(0, 8) + "…" + s.slice(-8) : s) : "—");

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4" onClick={onClose}>
      <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg border border-border bg-background p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-3 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <div className="truncate text-sm font-semibold text-foreground">ℹ️ Инфо об инстансе — {name || roomID}</div>
            <div className="truncate text-[11px] text-muted-foreground">{clientID} · <span className="font-mono">{roomID}</span></div>
          </div>
          <button type="button" className="rounded px-2 text-muted-foreground hover:bg-muted" onClick={onClose}>✕</button>
        </div>

        {/* Состояние инстанса */}
        <section className="mb-3 grid gap-2 rounded-md border border-border bg-card/40 p-3 text-xs">
          <div className="font-semibold text-foreground">⚙️ Состояние</div>
          <div className="grid grid-cols-2 gap-x-4 gap-y-1 sm:grid-cols-3">
            <div><span className="text-muted-foreground">Статус:</span> <span className={runtime?.running ? "text-emerald-500 font-medium" : "text-muted-foreground"}>{runtime?.status || "—"}</span></div>
            <div><span className="text-muted-foreground">Аптайм:</span> {runtime?.running ? olcFmtUptime(runtime?.started_at) : "—"}</div>
            <div><span className="text-muted-foreground">Память:</span> {runtime?.memory_bytes ? olcFmtBytes(runtime.memory_bytes) : "—"}</div>
            <div><span className="text-muted-foreground">PID:</span> {runtime?.pid || "—"}</div>
            <div><span className="text-muted-foreground">Рестартов:</span> {typeof runtime?.restarts === "number" ? runtime.restarts : "—"}</div>
            <div><span className="text-muted-foreground">Лог-строк:</span> {runtime?.log_count ?? "—"}</div>
          </div>
          {runtime?.exit_error && <div className="text-destructive">Ошибка выхода: {runtime.exit_error}</div>}
        </section>

        {/* Трафик */}
        <section className="mb-3 grid gap-1 rounded-md border border-border bg-card/40 p-3 text-xs">
          <div className="font-semibold text-foreground">📊 Трафик</div>
          {traffic?.available
            ? <div><span className="text-muted-foreground">Передано (этот инстанс):</span> <span className="font-medium">{olcFmtBytes(traffic.used_bytes)}</span></div>
            : <div className="text-muted-foreground">Учёт по инстансу недоступен (нужны квоты/netns для инстанса). Суммарный трафик клиента — в карточке клиента.</div>}
        </section>

        {/* Активные подключения сейчас */}
        <section className="mb-3 grid gap-1 rounded-md border border-border bg-card/40 p-3 text-xs">
          <div className="flex items-center gap-2 font-semibold text-foreground">🔌 Активны сейчас <span className="rounded bg-emerald-500/15 px-1.5 text-[10px] text-emerald-500">● живой статус</span></div>
          {peers.count > 0
            ? <div className="grid gap-0.5">
                <div><span className="text-muted-foreground">Устройств онлайн:</span> <span className="font-medium">{peers.count}</span></div>
                {peers.devices.length > 0 && <div className="flex flex-wrap gap-1">{peers.devices.map((d, i) => <span key={i} className="rounded border border-emerald-500/40 bg-emerald-500/10 px-1.5 py-0.5 font-mono text-[10px] text-emerald-400">{d}</span>)}</div>}
              </div>
            : <div className="text-muted-foreground">Нет активных подключений</div>}
        </section>

        {/* Журнал по устройствам (этот инстанс) */}
        <section className="mb-3 grid gap-2 rounded-md border border-border bg-card/40 p-3 text-xs">
          <div className="flex items-center justify-between gap-2">
            <div className="font-semibold text-foreground">📖 Журнал устройств (этот инстанс)</div>
            <div className="flex gap-1">
              {!autologi && <button type="button" className="rounded border border-border px-2 py-0.5 hover:bg-muted" onClick={() => void loadConns()}>Обновить</button>}
              <button type="button" className="rounded border border-destructive/40 px-2 py-0.5 text-destructive hover:bg-destructive/10" onClick={() => void clearJournal()}>Очистить</button>
            </div>
          </div>
          {autologi
            ? <div className="text-[10px] text-emerald-500/80">Автологи включены — журнал обновляется автоматически.</div>
            : <div className="text-[10px] text-muted-foreground">Автологи выключены — жмите «Обновить».</div>}
          {conns.length === 0
            ? <div className="text-muted-foreground">Записей нет</div>
            : <div className="grid gap-1 max-h-48 overflow-y-auto">
                {conns.map((rec, i) => (
                  <div key={i} className="rounded border border-border bg-background px-2 py-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="min-w-0 flex-1 truncate font-mono text-[11px]">{rec.device}</span>
                      {rec.count > 0 && <span className="rounded bg-emerald-500/15 px-1.5 text-[10px] text-emerald-500">✅ ×{rec.count}</span>}
                      {rec.denied > 0 && <span className="rounded bg-red-500/15 px-1.5 text-[10px] text-red-500">🚫 отклонено ×{rec.denied}</span>}
                      {rec.kicked > 0 && <span className="rounded bg-amber-500/15 px-1.5 text-[10px] text-amber-500">👢 кик ×{rec.kicked}</span>}
                      {(!rec.count && !rec.denied && !rec.kicked) && <span className="text-[10px] text-muted-foreground">только отклонённые попытки</span>}
                    </div>
                    <div className="mt-0.5 text-[10px] text-muted-foreground">
                      {rec.first && <>первое: {new Date(rec.first).toLocaleString()} · </>}
                      {rec.last && <>последнее: {new Date(rec.last).toLocaleString()}</>}
                    </div>
                  </div>
                ))}
              </div>}
        </section>

        {/* Ключи + рандомизация */}
        <section className="grid gap-2 rounded-md border border-border bg-card/40 p-3 text-xs">
          <div className="font-semibold text-foreground">🔑 Ключи шифрования</div>
          <div className="grid gap-1">
            <div className="flex items-center gap-2">
              <span className="text-muted-foreground shrink-0">Оригинальный:</span>
              <span className="min-w-0 flex-1 truncate font-mono text-[11px]">{showOrig ? (info?.orig_key || "—") : mask(info?.orig_key)}</span>
              <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => setShowOrig((v) => !v)}>{showOrig ? "скрыть" : "показать"}</button>
              {info?.orig_key && <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => { void olcSafeCopy(info.orig_key); setMsg("Ключ скопирован"); }}>копировать</button>}
            </div>
            <div className="grid gap-1">
              <span className="text-muted-foreground">Рандомизированный:</span>
              {!kr?.enabled
                ? <span className="text-muted-foreground">Рандомизация ключей выключена</span>
                : kr?.rand_type === 2
                  ? <div className="grid gap-0.5">
                      <div className="flex items-center gap-2">
                        <span className="rounded bg-sky-500/15 px-1.5 text-[10px] text-sky-400">🔄 тип 2 · посекундно</span>
                        <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-sky-300">{showRand ? (kr?.randomized_key || "…") : mask(kr?.randomized_key)}</span>
                        <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => setShowRand((v) => !v)}>{showRand ? "скрыть" : "показать"}</button>
                      </div>
                      <div className="text-[10px] text-muted-foreground">Меняется каждую секунду (значение выше обновляется live).</div>
                    </div>
                  : <div className="flex items-center gap-2">
                      <span className="rounded bg-emerald-500/15 px-1.5 text-[10px] text-emerald-500">🔒 тип 1 · статичный</span>
                      <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-emerald-300">{showRand ? (kr?.randomized_key || "—") : mask(kr?.randomized_key)}</span>
                      <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => setShowRand((v) => !v)}>{showRand ? "скрыть" : "показать"}</button>
                      {kr?.randomized_key && <button type="button" className="shrink-0 rounded border border-border px-1.5 py-0.5 text-[10px] hover:bg-muted" onClick={() => { void olcSafeCopy(kr.randomized_key); setMsg("Ключ скопирован"); }}>копировать</button>}
                    </div>}
            </div>
          </div>
          <div className="text-[10px] leading-snug text-muted-foreground">Рандомизированная версия ключа отражает текущую рандомизацию клиента (тип 1 — статичная, тип 2 — меняется каждую секунду). Оригинальный ключ инстанса ротирует только «♻️ Автосмена ключей».</div>
        </section>

        {msg && <div className="mt-2 text-[11px] text-amber-500">{msg}</div>}
      </div>
    </div>
  );
}

'''
if comp_guard in t:
    print("[patch-instance-info] component: already applied")
elif comp_anchor in t:
    t = t.replace(comp_anchor, comp_block + comp_anchor, 1); changed = True
    print("[patch-instance-info] component: ok")
else:
    print("[patch-instance-info] WARN component: anchor not found")

# --- 4. State instanceInfoTarget ---
repl(
    '  const [qrTarget, setQrTarget] = useState<{ clientID: string; location: LocationState } | null>(null);',
    '''  const [qrTarget, setQrTarget] = useState<{ clientID: string; location: LocationState } | null>(null);
  const [instanceInfoTarget, setInstanceInfoTarget] = useState<{ clientID: string; location: LocationState } | null>(null);''',
    "state instanceInfoTarget",
    guard="const [instanceInfoTarget, setInstanceInfoTarget]",
)

# --- 5. Заменить кнопку OlcBox на Info ---
repl(
    '''                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                                      disabled={busy}
                                      onClick={() => copyOlcBoxLink(client.client_id, loc.uri)}
                                    >
                                      <Copy className="h-4 w-4" />
                                      {t("olcBox")}
                                    </button>''',
    '''                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-sky-500/40 bg-sky-500/5 px-2 text-sm text-sky-500 hover:bg-sky-500/15 disabled:opacity-60"
                                      disabled={busy}
                                      title="Инфо, статистика и ключи инстанса"
                                      onClick={() => setInstanceInfoTarget({ clientID: client.client_id, location: loc })}
                                    >
                                      <Info className="h-4 w-4" />
                                      Info
                                    </button>''',
    "OlcBox->Info button",
    guard='onClick={() => setInstanceInfoTarget({ clientID: client.client_id, location: loc })}',
)

# --- 6. F5 persist: add instanceInfo + clientQr(subQr) to chain ---
repl(
    '    else if (logTarget) d = { k: "instanceLogs", id: logTarget.clientID, room: logTarget.location.room_id };',
    '''    else if (instanceInfoTarget) d = { k: "instanceInfo", id: instanceInfoTarget.clientID, room: instanceInfoTarget.location.room_id };
    else if (subQrTarget) d = { k: "clientQr", id: subQrTarget };
    else if (logTarget) d = { k: "instanceLogs", id: logTarget.clientID, room: logTarget.location.room_id };''',
    "F5 persist chain",
    guard='k: "instanceInfo"',
)
repl(
    '  }, [showSettings, createOpen, editClient, createLocationClient, editLocation, qrTarget, logTarget, clientLogTarget]);',
    '  }, [showSettings, createOpen, editClient, createLocationClient, editLocation, qrTarget, instanceInfoTarget, subQrTarget, logTarget, clientLogTarget]);',
    "F5 persist deps",
    guard="editLocation, qrTarget, instanceInfoTarget, subQrTarget, logTarget",
)

# --- 7. F5 restore switch: add cases ---
repl(
    '      case "instanceLogs": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) void openLogs(d.id, loc); break; }',
    '''      case "instanceInfo": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) setInstanceInfoTarget({ clientID: d.id, location: loc }); break; }
      case "clientQr": { const c = findClient(d.id); if (c) setSubQrTarget(d.id); break; }
      case "instanceLogs": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) void openLogs(d.id, loc); break; }''',
    "F5 restore switch",
    guard='case "instanceInfo":',
)

# --- 8. Рендер модалки (перед {qrTarget && () ---
repl(
    '''      {qrTarget && (
        <Modal title={`QR ${qrTarget.clientID}`} onClose={() => setQrTarget(null)}>''',
    '''      {instanceInfoTarget && (
        <InstanceInfoModal
          clientID={instanceInfoTarget.clientID}
          roomID={instanceInfoTarget.location.room_id}
          name={instanceInfoTarget.location.name}
          autologi={autologi}
          onClose={() => setInstanceInfoTarget(null)}
        />
      )}
      {qrTarget && (
        <Modal title={`QR ${qrTarget.clientID}`} onClose={() => setQrTarget(null)}>''',
    "render InstanceInfoModal",
    guard="<InstanceInfoModal",
)

# --- 9. Импорт иконки Info ---
if '\n  Info,\n' not in t:
    repl('  Copy,\n', '  Copy,\n  Info,\n', "import Info icon", guard=None)

if changed:
    f.write_text(t)
    print("[patch-instance-info] OK: main.tsx updated")
else:
    print("[patch-instance-info] no changes")
PY
