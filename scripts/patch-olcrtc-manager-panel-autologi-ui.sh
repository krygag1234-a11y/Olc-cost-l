#!/usr/bin/env bash
# Batch 3 (autologi) + Batch 2 (UI memory) frontend:
#  * autologi: load /api/settings/logs; when ON, all log views auto-tail and the
#    LIVE/Refresh buttons are hidden. When OFF, buttons show and LIVE persists.
#  * single shared LIVE across all log modals (localStorage), so toggling LIVE in
#    one modal is reflected everywhere after reopen/reload.
#  * remember expand state of Выборочная/Subscription randomization panels.
# Idempotent. Target: manager src/main.tsx. Run after subscription-ui + sync.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-autologi-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard and guard in t:
        print(f"[patch-autologi-ui] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-autologi-ui] {label}: ok")
    else:
        print(f"[patch-autologi-ui] WARN {label}: anchor not found")

# --- 1. storage key for shared LIVE ---
repl(
    'const LOGS_VERBOSE_STORAGE_KEY = "olc-panel-logs-verbose-v1";',
    'const LOGS_VERBOSE_STORAGE_KEY = "olc-panel-logs-verbose-v1";\nconst LOGS_LIVE_STORAGE_KEY = "olc-panel-logs-live-v1";',
    "LIVE storage key",
    guard='LOGS_LIVE_STORAGE_KEY',
)

# --- 2. App state: unify live + add autologi (keeps downstream refs working) ---
repl(
    '''  const [instanceLogsLive, setInstanceLogsLive] = useState(false);
  const [clientLogsLive, setClientLogsLive] = useState(false);''',
    '''  const [logsLive, setLogsLiveRaw] = useState(() => readStoredBool(LOGS_LIVE_STORAGE_KEY, false));
  const setLogsLive = useCallback(
    (v: boolean | ((prev: boolean) => boolean)) => {
      setLogsLiveRaw((prev) => {
        const next = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v;
        writeStoredBool(LOGS_LIVE_STORAGE_KEY, next);
        return next;
      });
    },
    [],
  );
  const [autologi, setAutologi] = useState(true);
  // effective LIVE: autologi forces continuous tailing; otherwise the user's LIVE toggle
  const instanceLogsLive = autologi || logsLive;
  const clientLogsLive = autologi || logsLive;
  const setInstanceLogsLive = setLogsLive;
  const setClientLogsLive = setLogsLive;''',
    "unify live states + autologi",
    guard='const [autologi, setAutologi]',
)

# --- 3. panel-expand memory (subscription + selective) ---
repl(
    '  const [subscriptionRandomizationOpen, setSubscriptionRandomizationOpen] = useState(false);',
    '  const [subscriptionRandomizationOpen, setSubscriptionRandomizationOpen] = useState(() => readStoredBool("olc-sub-rand-open-v1", false));',
    "subscription-open init",
    guard='olc-sub-rand-open-v1',
)
repl(
    '  const [selectiveRandomizationOpen, setSelectiveRandomizationOpen] = useState(false);',
    '  const [selectiveRandomizationOpen, setSelectiveRandomizationOpen] = useState(() => readStoredBool("olc-sel-rand-open-v1", false));',
    "selective-open init",
    guard='olc-sel-rand-open-v1',
)
repl(
    'onClick={() => setSubscriptionRandomizationOpen(!subscriptionRandomizationOpen)}',
    'onClick={() => { const v = !subscriptionRandomizationOpen; setSubscriptionRandomizationOpen(v); writeStoredBool("olc-sub-rand-open-v1", v); }}',
    "subscription-open persist",
)
repl(
    'onClick={() => setSelectiveRandomizationOpen(!selectiveRandomizationOpen)}',
    'onClick={() => { const v = !selectiveRandomizationOpen; setSelectiveRandomizationOpen(v); writeStoredBool("olc-sel-rand-open-v1", v); }}',
    "selective-open persist",
)

# --- 4. load autologi in loadSettings (after global randomization load) ---
repl(
    '''      setGlobalRandomizationEnabled(randBody.enabled ?? false);
    } catch {
      setGlobalRandomizationEnabled(false);
    }''',
    '''      setGlobalRandomizationEnabled(randBody.enabled ?? false);
    } catch {
      setGlobalRandomizationEnabled(false);
    }

    // Load autologi (auto-refresh logs) state
    try {
      const logsRes = await request("/api/settings/logs", { cache: "no-store" });
      const logsBody = (await logsRes.json()) as { auto_refresh?: boolean };
      setAutologi(logsBody.auto_refresh ?? true);
    } catch {
      setAutologi(true);
    }''',
    "load autologi",
    guard='// Load autologi (auto-refresh logs) state',
)

# --- 5. Settings modal: Автологи toggle row (before Выборочная рандомизация) ---
autologi_row = '''                        <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Автологи</div>
                <div className="text-xs text-muted-foreground">Логи обновляются автоматически везде; кнопки LIVE/Обновить скрыты</div>
              </div>
              <label className="inline-flex items-center gap-2 text-xs cursor-pointer">
                <input
                  type="checkbox"
                  checked={autologi}
                  onChange={async () => {
                    const newVal = !autologi;
                    setAutologi(newVal);
                    try {
                      await request("/api/settings/logs", {
                        method: "PATCH",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ auto_refresh: newVal }),
                      });
                    } catch {
                      setAutologi(!newVal);
                    }
                  }}
                  className="cursor-pointer"
                />
                <span className={autologi ? "text-emerald-600 font-medium" : ""}>{autologi ? "Вкл" : "Выкл"}</span>
              </label>
            </div>
                        <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Выборочная рандомизация</div>'''
repl(
    '''                        <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Выборочная рандомизация</div>''',
    autologi_row,
    "settings autologi row",
    guard='<div className="text-sm font-medium">Автологи</div>',
)

# --- 6. Hide client-logs LIVE/Refresh buttons when autologi ---
client_btns_old = '''              <button
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
              </button>'''
client_btns_new = '''              {autologi ? (
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
              )}'''
repl(client_btns_old, client_btns_new, "client-logs buttons hide")

# --- 7. Hide instance-logs LIVE/Refresh buttons when autologi ---
inst_btns_old = '''                <button
                  className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-50"
                  disabled={instanceLogsLive}
                  onClick={() => openLogs(logTarget.clientID, logTarget.location)}
                >
                  {t("refresh")}
                </button>
                <button
                  className={`h-9 rounded-md border border-border px-3 text-sm hover:bg-muted/80 ${
                    instanceLogsLive ? "bg-primary text-primary-foreground" : "bg-muted"
                  }`}
                  onClick={() => setInstanceLogsLive((value) => !value)}
                >
                  {instanceLogsLive ? t("logsLiveOn") : t("logsLive")}
                </button>'''
inst_btns_new = '''                {autologi ? (
                  <span className="inline-flex items-center rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-1 text-xs text-emerald-600">Автообновление</span>
                ) : (
                  <>
                    <button
                      className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-50"
                      disabled={instanceLogsLive}
                      onClick={() => openLogs(logTarget.clientID, logTarget.location)}
                    >
                      {t("refresh")}
                    </button>
                    <button
                      className={`h-9 rounded-md border border-border px-3 text-sm hover:bg-muted/80 ${
                        instanceLogsLive ? "bg-primary text-primary-foreground" : "bg-muted"
                      }`}
                      onClick={() => setInstanceLogsLive((value) => !value)}
                    >
                      {instanceLogsLive ? t("logsLiveOn") : t("logsLive")}
                    </button>
                  </>
                )}'''
repl(inst_btns_old, inst_btns_new, "instance-logs buttons hide")

# --- 8. FeatureLogsModal: fetch autologi itself (component not in App scope) ---
repl(
    '  const [live, setLive] = useState(false);',
    '''  const [liveRaw, setLiveRaw] = useState(() => readStoredBool(LOGS_LIVE_STORAGE_KEY, false));
  const [autologi, setAutologi] = useState(true);
  useEffect(() => {
    void fetch("/api/settings/logs", { cache: "no-store" })
      .then((r) => r.json())
      .then((b: { auto_refresh?: boolean }) => setAutologi(b.auto_refresh ?? true))
      .catch(() => setAutologi(true));
  }, []);
  const setLive = useCallback(
    (v: boolean | ((prev: boolean) => boolean)) => {
      setLiveRaw((prev) => {
        const next = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v;
        writeStoredBool(LOGS_LIVE_STORAGE_KEY, next);
        return next;
      });
    },
    [],
  );
  const live = autologi || liveRaw;''',
    "FeatureLogsModal autologi+shared live",
    guard='const live = autologi || liveRaw;',
)

# --- 10. FeatureLogsModal: hide Refresh/LIVE buttons when autologi ---
repl(
    '''            <button
              type="button"
              className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
              disabled={loading || live}
              onClick={() => void loadFeatureLogs(true)}
            >
              {t("refresh")}
            </button>
            <button
              type="button"
              className={`inline-flex items-center rounded-md border border-border px-2 py-1 text-xs hover:bg-accent ${
                live ? "bg-primary text-primary-foreground" : "bg-background"
              }`}
              onClick={() => setLive((value) => !value)}
            >
              {live ? t("logsLiveOn") : t("logsLive")}
            </button>''',
    '''            {autologi ? (
              <span className="inline-flex items-center rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2 py-1 text-xs text-emerald-600">Автообновление</span>
            ) : (
              <>
                <button
                  type="button"
                  className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
                  disabled={loading || live}
                  onClick={() => void loadFeatureLogs(true)}
                >
                  {t("refresh")}
                </button>
                <button
                  type="button"
                  className={`inline-flex items-center rounded-md border border-border px-2 py-1 text-xs hover:bg-accent ${
                    live ? "bg-primary text-primary-foreground" : "bg-background"
                  }`}
                  onClick={() => setLive((value) => !value)}
                >
                  {live ? t("logsLiveOn") : t("logsLive")}
                </button>
              </>
            )}''',
    "FeatureLogsModal buttons hide",
)

if changed:
    f.write_text(t)
print("[patch-autologi-ui] ok")
PY
