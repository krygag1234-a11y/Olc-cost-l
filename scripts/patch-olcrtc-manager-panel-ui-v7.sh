#!/usr/bin/env bash
# UI v7: notification modals, project check badge, stack patches, bridge poll, core settings.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-v7' "$MAIN_TSX" && grep -q 'Стек сервисов' "$MAIN_TSX" && { echo "[patch-panel-ui-v7] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
t = t.replace('/* olc-panel-ui-v6 */', '/* olc-panel-ui-v7 */', 1) if 'olc-panel-ui-v6' in t else t.replace(
    'import React, {', '/* olc-panel-ui-v7 */\nimport React, {', 1)

# Remove App listener that opens general settings from bell
t = t.replace(
    '''  useEffect(() => {
    const openNotifSettings = () => {
      void (async () => {
        setShowSettings(true);
        setNotice("");
        try {
          await loadSettings();
        } catch (err) {
          setNotice(err instanceof Error ? err.message : String(err));
        }
      })();
    };
    window.addEventListener("olc-open-notification-settings", openNotifSettings);
    return () => window.removeEventListener("olc-open-notification-settings", openNotifSettings);
  }, []);

''',
    '',
    1,
)

notif_modals = r'''
function AutodetectNotificationSettingsPanel({
  onClose,
}: {
  onClose?: () => void;
}) {
  const [s, setS] = useState<Record<string, unknown>>({});
  const [msg, setMsg] = useState("");
  useEffect(() => {
    void fetch("/api/notification-settings")
      .then((r) => r.json())
      .then((b: { settings?: Record<string, unknown> }) => setS(b.settings ?? {}));
  }, []);
  const save = async () => {
    const res = await fetch("/api/notification-settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(s),
    });
    setMsg(res.ok ? "Сохранено" : `HTTP ${res.status}`);
  };
  return (
    <div className="space-y-3 text-sm">
      <div className="font-medium">Автодетектор ошибок</div>
      <p className="text-xs text-muted-foreground">Сканирует логи и состояние сервисов, создаёт уведомления в колокольчике.</p>
      <label className="flex items-center gap-2 text-xs">
        <input type="checkbox" checked={Boolean(s.enabled)} onChange={(e) => setS({ ...s, enabled: e.target.checked })} />
        Включён
      </label>
      <label className="grid gap-1 text-xs text-muted-foreground">
        Интервал сканирования (сек)
        <input type="number" className="h-8 rounded border border-border bg-card px-2" value={Number(s.scan_interval_sec ?? 60)} onChange={(e) => setS({ ...s, scan_interval_sec: Number(e.target.value) })} />
      </label>
      <label className="grid gap-1 text-xs text-muted-foreground">
        Минимальная severity
        <select className="h-8 rounded border border-border bg-card px-2" value={String(s.min_severity ?? "warning")} onChange={(e) => setS({ ...s, min_severity: e.target.value })}>
          <option value="warning">warning и выше</option>
          <option value="error">только error</option>
        </select>
      </label>
      {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
      <div className="flex gap-2">
        <button type="button" className="rounded border border-primary px-3 py-1 text-xs text-primary" onClick={() => void save()}>
          Сохранить
        </button>
        {onClose && (
          <button type="button" className="rounded border border-border px-3 py-1 text-xs" onClick={onClose}>
            Закрыть
          </button>
        )}
      </div>
    </div>
  );
}

function NotificationPreferencesModal({ onClose }: { onClose: () => void }) {
  const [view, setView] = useState<"main" | "autodetect">("main");
  const [s, setS] = useState<Record<string, unknown>>({});
  const [msg, setMsg] = useState("");
  useEffect(() => {
    void fetch("/api/notification-settings")
      .then((r) => r.json())
      .then((b: { settings?: Record<string, unknown> }) => setS(b.settings ?? {}));
  }, []);
  const saveGeneral = async () => {
    const res = await fetch("/api/notification-settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(s),
    });
    setMsg(res.ok ? "Сохранено" : `HTTP ${res.status}`);
  };
  const sources = (s.sources as Record<string, boolean>) ?? {};
  const setSource = (k: string, v: boolean) => setS({ ...s, sources: { ...sources, [k]: v } });
  return (
    <Modal title={view === "main" ? "Настройки уведомлений" : "Автодетектор"} onClose={onClose}>
      <div className="max-h-[70vh] overflow-auto p-4">
        {view === "main" ? (
          <div className="space-y-3 text-sm">
            <label className="flex items-center gap-2 text-xs">
              <input type="checkbox" checked={Boolean(s.show_toast)} onChange={(e) => setS({ ...s, show_toast: e.target.checked })} />
              Всплывающие подсказки (toast)
            </label>
            <div className="text-xs font-medium text-muted-foreground">Источники для автодетектора</div>
            {["instance", "olcrtc", "tor", "zapret", "panel", "split"].map((k) => (
              <label key={k} className="flex items-center gap-2 text-xs">
                <input type="checkbox" checked={sources[k] !== false} onChange={(e) => setSource(k, e.target.checked)} />
                {k}
              </label>
            ))}
            <button type="button" className="w-full rounded border border-border px-3 py-2 text-left text-xs hover:bg-muted" onClick={() => setView("autodetect")}>
              Настройки автодетектора →
            </button>
            {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
            <button type="button" className="rounded border border-primary px-3 py-1 text-xs text-primary" onClick={() => void saveGeneral()}>
              Сохранить
            </button>
          </div>
        ) : (
          <>
            <button type="button" className="mb-3 text-xs text-primary hover:underline" onClick={() => setView("main")}>
              ← Назад к общим уведомлениям
            </button>
            <AutodetectNotificationSettingsPanel />
          </>
        )}
      </div>
    </Modal>
  );
}

function AutodetectNotificationSettingsModal({ onClose }: { onClose: () => void }) {
  return (
    <Modal title="Автодетектор" onClose={onClose}>
      <div className="p-4">
        <AutodetectNotificationSettingsPanel onClose={onClose} />
      </div>
    </Modal>
  );
}

'''

if 'NotificationPreferencesModal' not in t:
    t = t.replace('function NotificationSettingsSection()', notif_modals + 'function NotificationSettingsSection()', 1)

# Replace NotificationSettingsSection with stub that only opens autodetect modal via event
t = t.replace(
    '''function NotificationSettingsSection() {
  const [s, setS] = useState<Record<string, unknown>>({});
  const [msg, setMsg] = useState("");
  useEffect(() => {
    void fetch("/api/notification-settings")
      .then((r) => r.json())
      .then((b: { settings?: Record<string, unknown> }) => setS(b.settings ?? {}));
  }, []);
  const save = async () => {
    const res = await fetch("/api/notification-settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(s),
    });
    setMsg(res.ok ? "Сохранено" : `HTTP ${res.status}`);
  };
  return (
    <>
    <div className="text-sm font-medium text-foreground">Автодетектор ошибок</div>
    <label className="flex items-center gap-2 text-xs">
      <input type="checkbox" checked={Boolean(s.enabled)} onChange={(e) => setS({ ...s, enabled: e.target.checked })} />
      Включён
    </label>
    <label className="grid gap-1 text-xs text-muted-foreground">
      Интервал сканирования (сек)
      <input type="number" className="h-8 rounded border border-border bg-card px-2" value={Number(s.scan_interval_sec ?? 60)} onChange={(e) => setS({ ...s, scan_interval_sec: Number(e.target.value) })} />
    </label>
    <label className="grid gap-1 text-xs text-muted-foreground">
      Минимальная severity
      <select className="h-8 rounded border border-border bg-card px-2" value={String(s.min_severity ?? "warning")} onChange={(e) => setS({ ...s, min_severity: e.target.value })}>
        <option value="warning">warning+</option>
        <option value="error">только error</option>
      </select>
    </label>
    {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
    <button type="button" className="rounded border border-primary px-3 py-1 text-xs text-primary" onClick={() => void save()}>
      Сохранить автодетектор
    </button>
    </>
  );
}''',
    '''function MainSettingsAutodetectLink() {
  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Автодетектор</div>
      <p className="text-xs text-muted-foreground">Периодически ищет ошибки в логах и состоянии сервисов.</p>
      <button
        type="button"
        className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted"
        onClick={() => window.dispatchEvent(new CustomEvent("olc-open-autodetect-settings"))}
      >
        Настройки уведомлений автодетектора
      </button>
    </section>
  );
}''',
    1,
)

# NotificationBell - own modal state
t = t.replace(
    'function NotificationBell() {\n  const [open, setOpen] = useState(false);',
    'function NotificationBell() {\n  const [open, setOpen] = useState(false);\n  const [prefsOpen, setPrefsOpen] = useState(false);',
    1,
)
t = t.replace(
    '''              <button type="button" className="text-xs text-primary hover:underline" onClick={() => { setOpen(false); window.dispatchEvent(new CustomEvent("olc-open-notification-settings")); }}>
                Настройки
              </button>''',
    '''              <button type="button" className="text-xs text-primary hover:underline" onClick={() => { setOpen(false); setPrefsOpen(true); }}>
                Настройки
              </button>''',
    1,
)
t = t.replace(
    '''      )}
    </div>
  );
}

function ProjectUpdateButton''',
    '''      )}
      {prefsOpen && <NotificationPreferencesModal onClose={() => setPrefsOpen(false)} />}
    </div>
  );
}

function ProjectUpdateButton''',
    1,
)

# App: autodetect modal listener
if 'olc-open-autodetect-settings' not in t.split('function App()')[1][:8000]:
    t = t.replace(
        '  const [showSettings, setShowSettings] = useState(false);',
        '  const [showSettings, setShowSettings] = useState(false);\n  const [autodetectSettingsOpen, setAutodetectSettingsOpen] = useState(false);',
        1,
    )
    t = t.replace(
        '  const checkAuth = async () => {',
        '''  useEffect(() => {
    const h = () => setAutodetectSettingsOpen(true);
    window.addEventListener("olc-open-autodetect-settings", h);
    return () => window.removeEventListener("olc-open-autodetect-settings", h);
  }, []);

  const checkAuth = async () => {''',
        1,
    )
    t = t.replace(
        '      {showSettings && (',
        '      {autodetectSettingsOpen && <AutodetectNotificationSettingsModal onClose={() => setAutodetectSettingsOpen(false)} />}\n      {showSettings && (',
        1,
    )
    t = t.replace(
        '''            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <NotificationSettingsSection />
            </section>''',
        '            <MainSettingsAutodetectLink />',
        1,
    )

# Project modal: stack + check button
t = t.replace(
    '  const [err, setErr] = useState("");\n\n  const loadAll = async () => {',
    '  const [err, setErr] = useState("");\n  const [checkBusy, setCheckBusy] = useState(false);\n\n  const loadAll = async () => {',
    1,
)
t = t.replace(
    '''  useEffect(() => {
    if (!open) return;
    void loadAll();
    const id = window.setInterval(() => void loadAll(), 4000);
    return () => window.clearInterval(id);
  }, [open]);''',
    '''  useEffect(() => {
    void loadAll();
    const id = window.setInterval(() => void loadAll(), 30000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (!open) return;
    void loadAll();
    const id = window.setInterval(() => void loadAll(), 4000);
    return () => window.clearInterval(id);
  }, [open]);''',
    1,
)

stack_block = '''              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Стек сервисов</div>
                <div className="text-lg font-semibold">
                  {(stack.enabled as number) ?? 0}/{(stack.total as number) ?? 4}
                </div>
                <div className="mt-1 flex flex-wrap gap-1 text-[10px]">
                  {((stack.items as { id?: string; enabled?: boolean; label?: string }[]) ?? []).map((it) => (
                    <span key={it.id} className={`rounded px-1.5 py-0.5 ${it.enabled ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-600/30"}`}>
                      {it.label ?? it.id}
                    </span>
                  ))}
                </div>
                <p className="mt-1 text-[10px] text-muted-foreground">Zapret · Tor · Split · Мосты (WARP — опционально)</p>
              </div>'''

t = t.replace(
    '''              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Патчи (скрипты)</div>
                <div className="text-lg font-semibold">
                  {patches.applied_estimate ?? 0}/{patches.total_scripts ?? 0}
                </div>
                <div className="text-xs text-muted-foreground">оценка по наличию бинарников</div>
              </div>''',
    stack_block,
    1,
)

# Add stack variable
t = t.replace(
    '  const patches = (status?.patches as { total_scripts?: number; applied_estimate?: number }) ?? {};\n',
    '  const stack = (status?.stack ?? status?.patches) as { enabled?: number; total?: number; items?: { id?: string; label?: string; enabled?: boolean }[] } ?? {};\n',
    1,
)

t = t.replace(
    '''              <button type="button" className="rounded-md border border-border px-3 py-2" onClick={() => void loadAll()}>
                Обновить статус
              </button>''',
    '''              <button type="button" className="rounded-md border border-border px-3 py-2 disabled:opacity-50" disabled={checkBusy} onClick={() => { setCheckBusy(true); void loadAll().finally(() => setCheckBusy(false)); }}>
                {checkBusy ? "Проверка…" : "Проверить"}
              </button>
              <span className={`self-center text-xs ${status?.update_available ? "text-emerald-400" : "text-muted-foreground"}`}>
                {status?.update_available ? "● Доступно обновление" : status?.local_sha ? "● Актуальная версия" : ""}
              </span>''',
    1,
)

# BridgesSettingsFields - polling
t = t.replace(
    'function BridgesSettingsFields({\n  settings,\n  setSettings,\n  setMsg,\n}: {\n  settings: Record<string, unknown>;\n  setSettings: React.Dispatch<React.SetStateAction<Record<string, unknown>>>;\n  setMsg: (s: string) => void;\n}) {',
    'function BridgesSettingsFields({\n  settings,\n  setSettings,\n  setMsg,\n  onReload,\n}: {\n  settings: Record<string, unknown>;\n  setSettings: React.Dispatch<React.SetStateAction<Record<string, unknown>>>;\n  setMsg: (s: string) => void;\n  onReload: () => Promise<void>;\n}) {',
    1,
)

t = t.replace(
    '  const [newUrls, setNewUrls] = useState("");\n\n  const patchProfiles',
    '''  const [newUrls, setNewUrls] = useState("");
  const [poolBusy, setPoolBusy] = useState(false);
  const poolJob = (settings.pool_job as Record<string, unknown>) ?? {};
  const jobStatus = String(poolJob.status ?? "idle");

  useEffect(() => {
    if (jobStatus !== "running") return;
    const id = window.setInterval(() => void onReload(), 2500);
    return () => window.clearInterval(id);
  }, [jobStatus, onReload]);

  const patchProfiles''',
    1,
)

t = t.replace(
    '''  const refreshPool = async (types: string) => {
    const res = await fetch("/api/settings/bridges", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "refresh_pool", types }),
    });
    setMsg(res.ok ? "Обновление пула запущено" : `HTTP ${res.status}`);
  };''',
    '''  const refreshPool = async (types: string) => {
    setPoolBusy(true);
    setMsg("Загрузка пула и применение мостов…");
    try {
      const res = await fetch("/api/settings/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "refresh_pool", types }),
      });
      const body = (await res.json()) as { pool_job?: Record<string, unknown>; error?: string };
      if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
      setSettings((s) => ({ ...s, pool_job: body.pool_job }));
      setMsg("Обновление запущено — подождите…");
      await onReload();
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setPoolBusy(false);
    }
  };''',
    1,
)

# webtunnel warning + job status in bridges UI
t = t.replace(
    '''      <p className="text-xs text-muted-foreground">
        Пул: obfs4 {ps.obfs4 ?? 0}, webtunnel {ps.webtunnel ?? 0}, прочие {ps.other ?? 0}, всего {ps.total ?? 0}
      </p>''',
    '''      <p className="text-xs text-muted-foreground">
        Пул: obfs4 {ps.obfs4 ?? 0}, webtunnel {ps.webtunnel ?? 0}, прочие {ps.other ?? 0}, всего {ps.total ?? 0}
        {settings.webtunnel === false && String(sys.types ?? "").includes("webtunnel") && (
          <span className="block text-amber-400">webtunnel-client не установлен — скачивается с mirror-cry при обновлении</span>
        )}
      </p>
      {jobStatus === "running" && <p className="text-xs text-amber-400">Обновление пула…</p>}
      {jobStatus === "error" && <p className="text-xs text-destructive">{String(poolJob.error ?? "ошибка")}</p>}
      {jobStatus === "done" && poolJob.finished_at && (
        <p className="text-xs text-emerald-400">Готово {String(poolJob.finished_at).slice(11, 19)}</p>
      )}''',
    1,
)

if 'disabled={poolBusy || jobStatus === "running"}' not in t:
    t = t.replace(
        'onClick={() => void refreshPool(String(sys.types ?? "obfs4,webtunnel"))}',
        'disabled={poolBusy || jobStatus === "running"} onClick={() => void refreshPool(String(sys.types ?? "obfs4,webtunnel"))}',
        1,
    )

# Pass onReload to BridgesSettingsFields
t = t.replace(
    '<BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} />',
    '<BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const body = (await res.json()) as { settings?: Record<string, unknown> }; setSettings(body.settings ?? {}); }} />',
    1,
)

# Zapret core settings UI
if 'nfqws_config' not in t.split('feature === "zapret"')[1][:2500]:
    t = t.replace(
        '''                <p className="text-xs text-muted-foreground">
                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}
                </p>''',
        '''                <details className="text-xs">
                  <summary className="cursor-pointer text-muted-foreground">Ядро nfqws (config)</summary>
                  <pre className="mt-1 max-h-40 overflow-auto rounded border border-border bg-background p-2 font-mono text-[10px]">{String(settings.nfqws_config ?? "—")}</pre>
                </details>
                <p className="text-xs text-muted-foreground">
                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · hostlist: {String(settings.hostlist_user ?? "—")}
                </p>''',
        1,
    )

# Tor core settings
if 'socks_listen_address' not in t.split('feature === "tor"')[1][:2800]:
    t = t.replace(
        '''                <p className="text-xs text-muted-foreground">
                  SOCKS listen: {String(settings.socks_listen ?? "9050")} · мосты в torrc: {settings.bridges_enabled ? "да" : "нет"}
                </p>''',
        '''                <label className="grid gap-1 text-muted-foreground">
                  SocksPort
                  <input className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs" value={String(settings.socks_listen ?? "")} onChange={(e) => setStr("socks_listen", e.target.value)} placeholder="9050" />
                </label>
                <p className="text-xs text-muted-foreground">
                  TestSocks: {String(settings.test_socks ?? "—")} · SafeSocks: {String(settings.safe_socks ?? "—")} · DNS: {String(settings.dns_port ?? "—")}
                </p>
                <p className="text-xs text-muted-foreground">
                  webtunnel-client: {settings.webtunnel_client ? "да" : "нет"} · bridges.conf подключён: {settings.bridges_enabled ? "да" : "нет"}
                </p>''',
        1,
    )

p.write_text(t)
print("[patch-panel-ui-v7] ok")
PY
