#!/usr/bin/env bash
# UI v5: project dashboard, notification settings, olcrtc row, bridges profiles, expanded forms.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-v5' "$MAIN_TSX" && { echo "[patch-panel-ui-v5] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# olc-panel-ui-v5
t = t.replace(
    '    { name: "webtunnel", label: "WebTunnel bridges", hint: "prebuilt binary from mirror-cry" },',
    '    { name: "webtunnel", label: "Мосты", hint: "obfs4 + webtunnel, пул и профили" },',
    1,
)

# Remove section refresh button
old_refresh = '''        <button
          className="inline-flex h-8 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
          disabled={busy !== null}
          onClick={() => void load()}
        >
          Обновить
        </button>
      </div>'''
if old_refresh in t:
    t = t.replace(old_refresh, '      </div>', 1)

# Add Olcrtc row before closing grid - insert before logFeature modals in FeaturesPanel
olcrtc_block = '''
          <div className="col-span-full my-1 border-t border-border" />
          <div className="col-span-full flex flex-wrap items-center justify-between gap-3 rounded-md border border-dashed border-border bg-background p-3">
            <div>
              <div className="font-medium">OlcRTC (ядро)</div>
              <div className="text-xs text-muted-foreground">panel.env, Jitsi TLS, split lists — ветка fix/all</div>
            </div>
            <div className="flex gap-1">
              <button type="button" title="Логи olcrtc" className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted" onClick={() => setLogFeature("zapret")}>
                <Terminal className="h-4 w-4" />
              </button>
              <button type="button" title="Настройки OlcRTC" className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted" onClick={() => setSettingsFeature("olcrtc" as FeatureName)}>
                <Settings className="h-4 w-4" />
              </button>
            </div>
          </div>
'''
if 'OlcRTC (ядро)' not in t:
    t = t.replace(
        '        </div>\n      )}\n      {logFeature && <FeatureLogsModal',
        '        </div>\n      )}' + olcrtc_block + '\n      {logFeature && <FeatureLogsModal',
        1,
    )

# Extend FeatureName type - grep type FeatureName
if '"olcrtc"' not in t.split('type FeatureName')[1].split(';')[0]:
    t = t.replace(
        'type FeatureName = "zapret" | "tor" | "split" | "webtunnel";',
        'type FeatureName = "zapret" | "tor" | "split" | "webtunnel" | "olcrtc";',
        1,
    )

# FeatureSettingsModal apiName for olcrtc
t = t.replace(
    '  const apiName = feature === "webtunnel" ? "bridges" : feature;',
    '  const apiName = feature === "webtunnel" ? "bridges" : feature === "olcrtc" ? "olcrtc" : feature;',
    1,
)

# Notification bell settings link
if 'Настройки уведомлений' not in t:
    t = t.replace(
        '''          <div className="flex items-center justify-between border-b border-border px-3 py-2 text-sm font-medium">
            Уведомления
            <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => setOpen(false)}>
              Закрыть
            </button>
          </div>''',
        '''          <div className="flex items-center justify-between border-b border-border px-3 py-2 text-sm font-medium">
            <span>Уведомления</span>
            <div className="flex gap-2">
              <button type="button" className="text-xs text-primary hover:underline" onClick={() => { setOpen(false); window.dispatchEvent(new CustomEvent("olc-open-notification-settings")); }}>
                Настройки
              </button>
              <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => setOpen(false)}>
                Закрыть
              </button>
            </div>
          </div>''',
        1,
    )

# Replace ProjectUpdateButton with richer version - find function and replace whole function
start = t.find('function ProjectUpdateButton')
end = t.find('const COMPONENT_DRAWER_ITEMS')
if start > 0 and end > start:
    new_project = r'''function ProjectUpdateButton({ disabled }: { disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<Record<string, unknown> | null>(null);
  const [job, setJob] = useState<{ job_id?: string; status?: string } | null>(null);
  const [logLines, setLogLines] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  const loadAll = async () => {
    setErr("");
    try {
      const res = await fetch("/api/project/status", { cache: "no-store" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
      setStatus(body as Record<string, unknown>);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    }
    const sr = await fetch("/api/updates/status", { cache: "no-store" });
    if (sr.ok) {
      const b = (await sr.json()) as { job?: { job_id?: string; status?: string }; locked?: boolean };
      if (b.job) setJob(b.job);
      if (b.locked && b.job?.job_id) {
        const lr = await fetch(`/api/jobs/${encodeURIComponent(b.job.job_id)}/log`, { cache: "no-store" });
        if (lr.ok) {
          const lj = (await lr.json()) as { lines?: string[] };
          setLogLines(lj.lines ?? []);
        }
      }
    }
  };

  useEffect(() => {
    if (!open) return;
    void loadAll();
    const id = window.setInterval(() => void loadAll(), 4000);
    return () => window.clearInterval(id);
  }, [open]);

  const runUpdate = async () => {
    if (!window.confirm("Обновить Olc-cost-l с GitHub? Панель перезапустится (~2–10 мин).")) return;
    setBusy(true);
    try {
      const res = await fetch("/api/updates/run", { method: "POST" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
      setJob(body as { job_id?: string; status?: string });
      await loadAll();
    } catch (e) {
      alert(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  const patches = (status?.patches as { total_scripts?: number; applied_estimate?: number }) ?? {};
  const notif = (status?.notifications as { total?: number; errors?: number; unread?: number }) ?? {};
  const caps = (status?.capabilities as { flags?: Record<string, boolean> }) ?? {};

  return (
    <>
      <button
        type="button"
        disabled={disabled}
        className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
        onClick={() => setOpen(true)}
        title="Состояние проекта и обновление"
      >
        <Download className="h-4 w-4" />
        Проект
        {Boolean(status?.update_available) && <span className="h-2 w-2 rounded-full bg-emerald-400" title="Доступно обновление" />}
      </button>
      {open && (
        <Modal title="Состояние проекта" onClose={() => setOpen(false)}>
          <div className="max-h-[70vh] space-y-4 overflow-auto p-4 text-sm">
            {err && <p className="text-destructive">{err}</p>}
            <div className="grid gap-3 md:grid-cols-3">
              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Версия панели</div>
                <div className="text-lg font-semibold">{String(status?.panel_version ?? "—")}</div>
                <div className="text-xs text-muted-foreground">профиль: {String(status?.deploy_profile ?? "—")}</div>
              </div>
              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Патчи (скрипты)</div>
                <div className="text-lg font-semibold">
                  {patches.applied_estimate ?? 0}/{patches.total_scripts ?? 0}
                </div>
                <div className="text-xs text-muted-foreground">оценка по наличию бинарников</div>
              </div>
              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Автодетектор</div>
                <div className="text-lg font-semibold">{notif.errors ?? 0} ошибок</div>
                <div className="text-xs text-muted-foreground">всего {notif.total ?? 0}, непрочит. {notif.unread ?? 0}</div>
              </div>
            </div>
            <div className="rounded border border-border p-3 text-xs">
              <div className="mb-1 font-medium">Git</div>
              <div>
                локально: <code>{String(status?.local_sha ?? "—").slice(0, 12)}</code>
                {status?.remote_sha ? (
                  <>
                    {" "}
                    → удалённо: <code>{String(status.remote_sha).slice(0, 12)}</code>
                  </>
                ) : (
                  <span className="text-muted-foreground"> (remote недоступен — проверьте git на VPS)</span>
                )}
              </div>
              {Boolean(status?.update_available) && <p className="mt-1 text-emerald-400">Доступно обновление origin/main</p>}
            </div>
            <div className="rounded border border-border p-3 text-xs">
              <div className="mb-1 font-medium">Компоненты (флаги)</div>
              <div className="flex flex-wrap gap-2">
                {Object.entries(caps.flags ?? {}).map(([k, v]) => (
                  <span key={k} className={`rounded px-2 py-0.5 ${v ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-500/20"}`}>
                    {k}: {v ? "on" : "off"}
                  </span>
                ))}
              </div>
            </div>
            {(job?.status === "running" || status?.update_locked) && (
              <p className="text-amber-400">Обновление выполняется… не закрывайте вкладку до перезапуска панели.</p>
            )}
            <div className="flex flex-wrap gap-2">
              <button type="button" className="rounded-md border border-primary bg-primary/20 px-3 py-2 text-primary disabled:opacity-50" disabled={busy || Boolean(status?.update_locked)} onClick={() => void runUpdate()}>
                {busy ? "Запуск…" : "Обновить с GitHub"}
              </button>
              <button type="button" className="rounded-md border border-border px-3 py-2" onClick={() => void loadAll()}>
                Обновить статус
              </button>
            </div>
            {logLines.length > 0 && (
              <pre className="max-h-48 overflow-auto rounded border border-border bg-background p-2 text-xs">{logLines.slice(-50).join("\n")}</pre>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}

'''
    t = t[:start] + new_project + t[end:]

# Profile quick rename on StatCard
if 'function ProfileStatCard' not in t:
    t = t.replace(
        'function StatCard({',
        r'''function ProfileStatCard({
  name,
  onSave,
}: {
  name: string;
  onSave: (next: string) => Promise<void>;
}) {
  const [editing, setEditing] = useState(false);
  const [val, setVal] = useState(name);
  useEffect(() => setVal(name), [name]);
  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Server className="h-4 w-4" />
        <span>Профиль</span>
      </div>
      {editing ? (
        <div className="mt-2 flex gap-2">
          <input className="h-9 flex-1 rounded-md border border-border bg-background px-2 text-sm" value={val} onChange={(e) => setVal(e.target.value)} />
          <button type="button" className="rounded border border-primary px-2 text-xs text-primary" onClick={() => void onSave(val).then(() => setEditing(false))}>
            OK
          </button>
        </div>
      ) : (
        <button type="button" className="mt-2 block text-left text-2xl font-semibold hover:text-primary" onClick={() => setEditing(true)} title="Переименовать">
          {name || "…"}
        </button>
      )}
    </div>
  );
}

function StatCard({''',
        1,
    )

t = t.replace(
    '<StatCard icon={<Server className="h-4 w-4" />} label="Профиль" value={state?.name ?? "..."} />',
    '<ProfileStatCard name={state?.name ?? ""} onSave={async (next) => { await saveSettingsName(next); }} />',
    1,
)

# Add saveSettingsName in App - after saveSettings function
if 'saveSettingsName' not in t:
    t = t.replace(
        '  const saveSettings = async () => {',
        r'''  const saveSettingsName = async (name: string) => {
    const port = Number(settingsForm.port) || settings?.port || 8888;
    const res = await request("/api/settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: name.trim(),
        port,
        subscription_path: settingsForm.subscription_path.trim(),
        refresh: cleanRefresh(settingsForm.refresh),
      }),
    });
    const body = (await res.json()) as SettingsState;
    setSettings(body);
    setSettingsForm((f) => ({ ...f, name: body.name }));
    await loadState();
    setNotice("Профиль переименован");
  };

  const saveSettings = async () => {''',
        1,
    )

# Notification settings section in main settings modal + listener in App
notif_section = '''
            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <NotificationSettingsSection />
            </section>
'''
if 'NotificationSettingsSection' not in t:
    t = t.replace(
        '            <section className="grid gap-3 rounded-md border border-border bg-background p-4">\n              <div className="text-sm font-medium text-foreground">Пароль администратора</div>',
        notif_section + '\n            <section className="grid gap-3 rounded-md border border-border bg-background p-4">\n              <div className="text-sm font-medium text-foreground">Пароль администратора</div>',
        1,
    )

if 'function NotificationSettingsSection' not in t:
    notif_fn = r'''
function NotificationSettingsSection() {
  const [s, setS] = useState<Record<string, unknown>>({});
  const [msg, setMsg] = useState("");
  useEffect(() => {
    void fetch("/api/notification-settings")
      .then((r) => r.json())
      .then((b: { settings?: Record<string, unknown> }) => setS(b.settings ?? {}));
  }, []);
  useEffect(() => {
    const h = () => setShowNotifSettings(true);
    window.addEventListener("olc-open-notification-settings", h);
    return () => window.removeEventListener("olc-open-notification-settings", h);
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
}
'''
    t = t.replace('function NotificationBell()', notif_fn + '\nfunction NotificationBell()', 1)

if 'olcrtc:' not in t.split('FEATURE_SETTINGS_HINTS')[1][:500]:
    t = t.replace(
        '  webtunnel: {',
        '  olcrtc: {\n    title: "OlcRTC",\n    lines: ["panel.env, Jitsi TLS, публичный URL", "ветка fix/all"],\n  },\n  webtunnel: {',
        1,
    )

# Component settings: olcrtc + bridges profiles + zapret strategy - append before closing of ComponentSettingsModal forms
# Add olcrtc form block
if 'feature === "olcrtc"' not in t.split('ComponentSettingsModal')[1][:8000]:
    t = t.replace(
        '            {(feature === "webtunnel" || feature === "bridges") && (',
        r'''            {feature === "olcrtc" && (
              <>
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.jitsi_insecure_tls)} onChange={(e) => setBool("jitsi_insecure_tls", e.target.checked)} />
                  OLCRTC_JITSI_INSECURE_TLS (самоподписанные сертификаты Jitsi)
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Публичный URL панели (OLCRTC_PUBLIC_URL)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.public_url ?? "")} onChange={(e) => setStr("public_url", e.target.value)} placeholder="https://vps.example:8888" />
                </label>
                <p className="text-xs text-muted-foreground">Ветка olcrtc: fix/all (не master). После сохранения — olc-update или перезапуск инстансов.</p>
              </>
            )}
            {(feature === "webtunnel" || feature === "bridges") && (''',
        1,
    )

# Bridges: pool stats + profiles UI - replace bridges section opening
bridges_ui = r'''            {(feature === "webtunnel" || feature === "bridges") && (
              <>
                {(() => {
                  const ps = (settings.pool_stats as Record<string, number>) ?? {};
                  const prof = (settings.profiles as Record<string, unknown>) ?? {};
                  const sys = (prof.system as Record<string, unknown>) ?? {};
                  const custom = (prof.profiles as unknown[]) ?? [];
                  return (
                    <>
                      <p className="text-xs text-muted-foreground">
                        Пул: obfs4 {ps.obfs4 ?? 0}, webtunnel {ps.webtunnel ?? 0}, всего {ps.total ?? 0}
                      </p>
                      <div className="rounded border border-border p-2 text-xs">
                        <div className="font-medium">Системный профиль (нельзя удалить)</div>
                        <label className="mt-1 grid gap-1">
                          Типы мостов
                          <select className="h-8 rounded border border-border bg-background px-2" value={String(sys.types ?? "obfs4,webtunnel")} onChange={(e) => setSettings((s) => ({ ...s, bridge_profiles: { ...prof, system: { ...sys, types: e.target.value } } }))}>
                            <option value="obfs4">obfs4</option>
                            <option value="webtunnel">webtunnel</option>
                            <option value="obfs4,webtunnel">obfs4 + webtunnel</option>
                          </select>
                        </label>
                        <label className="mt-2 flex items-center gap-2">
                          <input type="checkbox" checked={Boolean(sys.auto_update)} onChange={(e) => setSettings((s) => ({ ...s, bridge_profiles: { ...prof, system: { ...sys, auto_update: e.target.checked } } }))} />
                          Автообновление пула (cron)
                        </label>
                        {!Boolean(sys.auto_update) && (
                          <button type="button" className="mt-2 rounded border border-border px-2 py-1" onClick={async () => {
                            await fetch(`/api/settings/bridges`, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "refresh_pool", types: sys.types }) });
                            setMsg("Обновление пула запущено");
                          }}>Обновить пул</button>
                        )}
                      </div>
                      {custom.length > 0 && <p className="text-xs">Кастомных профилей: {custom.length}</p>}
                    </>
                  );
                })()}'''
# Too complex replace - simpler patch for bridges only add pool line at start of bridges block
if 'Пул: obfs4' not in t:
    t = t.replace(
        '            {(feature === "webtunnel" || feature === "bridges") && (\n              <>\n                <label className="grid gap-1 text-muted-foreground">\n                  Добавить мост',
        r'''            {(feature === "webtunnel" || feature === "bridges") && (
              <>
                <p className="text-xs text-muted-foreground">
                  Пул: obfs4 {String((settings.pool_stats as Record<string, number>)?.obfs4 ?? 0)}, webtunnel {String((settings.pool_stats as Record<string, number>)?.webtunnel ?? 0)}
                </p>
                <label className="grid gap-1 text-muted-foreground">
                  Добавить мост''',
        1,
    )

p.write_text(t)
print("[patch-panel-ui-v5] ok")
PY
