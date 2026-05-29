#!/usr/bin/env bash
# Phase 4–6 UI: notifications bell, project update modal, components drawer.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-phase456-ui' "$MAIN_TSX" && { echo "[patch-phase456-ui] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if 'Bell,' not in t:
    t = t.replace(
        '  Users,\n  X,\n} from "lucide-react";',
        '  Users,\n  X,\n  Bell,\n  Package,\n  AlertTriangle,\n  Download,\n} from "lucide-react";',
        1,
    )

block = r'''
// olc-phase456-ui
type PanelNotification = {
  id: string;
  catalog_id?: string;
  severity?: string;
  title?: string;
  meaning?: string;
  fixes?: string[];
  read?: boolean;
};

function NotificationBell() {
  const [open, setOpen] = useState(false);
  const [list, setList] = useState<PanelNotification[]>([]);
  const [unread, setUnread] = useState(0);

  const load = async () => {
    try {
      const res = await fetch("/api/notifications", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as { notifications?: PanelNotification[]; unread?: number };
      setList(body.notifications ?? []);
      setUnread(body.unread ?? 0);
    } catch {
      /* ignore */
    }
  };

  useEffect(() => {
    void load();
    void fetch("/api/notifications/scan", { method: "POST" }).then(() => load());
    const id = window.setInterval(() => void load(), 60000);
    return () => window.clearInterval(id);
  }, []);

  const dismiss = async (id: string) => {
    await fetch(`/api/notifications/${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dismiss: true }),
    });
    await load();
  };

  const markRead = async (id: string) => {
    await fetch(`/api/notifications/${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ read: true }),
    });
    await load();
  };

  return (
    <div className="relative">
      <button
        type="button"
        className="relative inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
        onClick={() => setOpen((o) => !o)}
        title="Уведомления"
      >
        <Bell className="h-4 w-4" />
        {unread > 0 && (
          <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] text-white">
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </button>
      {open && (
        <div className="absolute right-0 z-50 mt-1 w-[min(24rem,90vw)] rounded-lg border border-border bg-card shadow-lg">
          <div className="flex items-center justify-between border-b border-border px-3 py-2 text-sm font-medium">
            Уведомления
            <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => setOpen(false)}>
              Закрыть
            </button>
          </div>
          <ul className="max-h-80 overflow-auto p-2 text-xs">
            {list.length === 0 && <li className="p-2 text-muted-foreground">Нет активных предупреждений</li>}
            {list.map((n) => (
              <li key={n.id} className="mb-2 rounded border border-border p-2">
                <div className="flex items-start justify-between gap-2">
                  <span className={n.severity === "error" ? "text-destructive" : "text-amber-400"}>{n.title}</span>
                  <button type="button" className="shrink-0 text-muted-foreground hover:text-foreground" onClick={() => void dismiss(n.id)}>
                    ×
                  </button>
                </div>
                {n.meaning && <p className="mt-1 text-muted-foreground">{n.meaning}</p>}
                <button type="button" className="mt-1 text-primary hover:underline" onClick={() => void markRead(n.id)}>
                  Прочитано
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function ProjectUpdateButton({ disabled }: { disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  const [check, setCheck] = useState<{ available?: boolean; local_sha?: string; remote_sha?: string; locked?: boolean } | null>(null);
  const [job, setJob] = useState<{ job_id?: string; status?: string } | null>(null);
  const [logLines, setLogLines] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);

  const loadCheck = async () => {
    const res = await fetch("/api/updates/check", { cache: "no-store" });
    if (res.ok) setCheck((await res.json()) as typeof check);
  };

  const loadStatus = async () => {
    const res = await fetch("/api/updates/status", { cache: "no-store" });
    if (!res.ok) return;
    const body = (await res.json()) as { job?: { job_id?: string; status?: string }; locked?: boolean };
    if (body.job) setJob(body.job);
    if (body.locked && body.job?.job_id) {
      const lr = await fetch(`/api/jobs/${encodeURIComponent(body.job.job_id)}/log`, { cache: "no-store" });
      if (lr.ok) {
        const lj = (await lr.json()) as { lines?: string[] };
        setLogLines(lj.lines ?? []);
      }
    }
  };

  useEffect(() => {
    if (!open) return;
    void loadCheck();
    void loadStatus();
    const id = window.setInterval(() => void loadStatus(), 3000);
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
    } catch (e) {
      alert(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

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
        {check?.available && <span className="h-2 w-2 rounded-full bg-emerald-400" title="Доступно обновление" />}
      </button>
      {open && (
        <Modal title="Состояние проекта" onClose={() => setOpen(false)}>
          <div className="space-y-3 p-4 text-sm">
            <p className="text-muted-foreground">
              Локально: <code className="text-xs">{check?.local_sha?.slice(0, 12) ?? "…"}</code>
              {check?.remote_sha && (
                <>
                  {" "}
                  → удалённо: <code className="text-xs">{check.remote_sha.slice(0, 12)}</code>
                </>
              )}
            </p>
            {check?.available && <p className="text-emerald-400">Доступно обновление с origin/main</p>}
            {job?.status === "running" || check?.locked ? (
              <p className="text-amber-400">Обновление выполняется… не закрывайте вкладку до перезапуска панели.</p>
            ) : null}
            <div className="flex gap-2">
              <button
                type="button"
                className="rounded-md border border-primary bg-primary/20 px-3 py-2 text-primary disabled:opacity-50"
                disabled={busy || Boolean(check?.locked)}
                onClick={() => void runUpdate()}
              >
                {busy ? "Запуск…" : "Обновить с GitHub"}
              </button>
              <button type="button" className="rounded-md border border-border px-3 py-2" onClick={() => void loadCheck()}>
                Проверить
              </button>
            </div>
            {logLines.length > 0 && (
              <pre className="max-h-48 overflow-auto rounded border border-border bg-background p-2 text-xs">
                {logLines.slice(-40).join("\n")}
              </pre>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}

const COMPONENT_DRAWER_ITEMS = [
  { id: "zapret", label: "Zapret (DPI)" },
  { id: "tor", label: "Tor" },
  { id: "split", label: "Split" },
  { id: "bridges", label: "Мосты" },
] as const;

function ComponentsDrawerButton() {
  const [open, setOpen] = useState(false);
  const { caps } = useCapabilities();
  const [jobMsg, setJobMsg] = useState("");

  const run = async (name: string, action: "install" | "uninstall") => {
    const word = action === "install" ? "установить" : "отключить";
    if (!window.confirm(`${word} ${name}? Может занять несколько минут.`)) return;
    setJobMsg("Запуск…");
    try {
      const res = await fetch(`/api/components/${name}/${action}`, { method: "POST" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
      setJobMsg(`Задача ${(body as { job_id?: string }).job_id} — см. лог на VPS`);
    } catch (e) {
      setJobMsg(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <>
      <button
        type="button"
        className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
        onClick={() => setOpen(true)}
        title="Установка и удаление компонентов"
      >
        <Package className="h-4 w-4" />
        ±
      </button>
      {open && (
        <Modal title="Компоненты VPS" onClose={() => setOpen(false)}>
          <div className="space-y-3 p-4 text-sm">
            <p className="text-xs text-muted-foreground">Профиль: {caps?.deploy_profile ?? "—"}</p>
            {COMPONENT_DRAWER_ITEMS.map((c) => {
              const st = caps?.components?.[c.id];
              const installed = st?.installed ?? false;
              return (
                <div key={c.id} className="flex flex-wrap items-center justify-between gap-2 rounded border border-border p-2">
                  <div>
                    <div className="font-medium">{c.label}</div>
                    <div className="text-xs text-muted-foreground">
                      {installed ? "установлен" : "не установлен"}
                      {st?.enabled ? " · вкл" : st?.installed ? " · выкл" : ""}
                    </div>
                  </div>
                  <div className="flex gap-2">
                    {!installed && (
                      <button
                        type="button"
                        className="rounded border border-primary px-2 py-1 text-xs text-primary"
                        onClick={() => void run(c.id, "install")}
                      >
                        Установить
                      </button>
                    )}
                    {installed && (
                      <button
                        type="button"
                        className="rounded border border-destructive px-2 py-1 text-xs text-destructive"
                        onClick={() => void run(c.id, "uninstall")}
                      >
                        Отключить
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
            {jobMsg && <p className="text-xs text-muted-foreground">{jobMsg}</p>}
          </div>
        </Modal>
      )}
    </>
  );
}

function ErrorsSummaryButton() {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<PanelNotification[]>([]);

  useEffect(() => {
    if (!open) return;
    void fetch("/api/notifications/scan", { method: "POST" })
      .then(() => fetch("/api/notifications", { cache: "no-store" }))
      .then((r) => r.json())
      .then((b: { notifications?: PanelNotification[] }) => setItems(b.notifications ?? []));
  }, [open]);

  const errors = items.filter((n) => n.severity === "error");

  return (
    <>
      <button
        type="button"
        className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
        onClick={() => setOpen(true)}
        title="Ошибки по каталогу"
      >
        <AlertTriangle className="h-4 w-4" />
        {errors.length > 0 && <span className="text-destructive">{errors.length}</span>}
      </button>
      {open && (
        <Modal title="Ошибки" onClose={() => setOpen(false)}>
          <ul className="max-h-96 space-y-2 overflow-auto p-4 text-sm">
            {errors.length === 0 && <li className="text-muted-foreground">Критичных ошибок не найдено в логах</li>}
            {errors.map((n) => (
              <li key={n.id} className="rounded border border-border p-2">
                <div className="font-medium text-destructive">{n.title}</div>
                <p className="text-xs text-muted-foreground">{n.meaning}</p>
                {n.fixes && n.fixes.length > 0 && (
                  <ul className="mt-1 list-disc pl-4 text-xs">
                    {n.fixes.map((f, i) => (
                      <li key={i}>{f}</li>
                    ))}
                  </ul>
                )}
              </li>
            ))}
          </ul>
        </Modal>
      )}
    </>
  );
}

'''

anchor = 'function App() {'
if 'olc-phase456-ui' not in t:
    t = t.replace(anchor, block + '\n' + anchor, 1)

# useCapabilities returns { visible, caps } - check actual return
if 'return { visible, caps' not in t and 'const { visible } = useCapabilities' in t:
    # patch useCapabilities to also return caps
    t = t.replace(
        '  return { visible };',
        '  return { visible, caps };',
        1,
    ) if '  return { visible };' in t else t

header_old = '''          <div className="flex flex-wrap items-center gap-2">
            <HeaderMetric label="Panel mem" value={formatBytes(metrics?.memory.heap_alloc_bytes)} />'''
header_new = '''          <div className="flex flex-wrap items-center gap-2">
            <ComponentsDrawerButton />
            <HeaderMetric label="Panel mem" value={formatBytes(metrics?.memory.heap_alloc_bytes)} />'''
if header_old in t and 'ComponentsDrawerButton' not in t.split('function App')[1][:2000]:
    t = t.replace(header_old, header_new, 1)

btn_old = '''            <button
              className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
              onClick={logout}
            >
              <LogOut className="h-4 w-4" />
              Выйти
            </button>'''
btn_new = '''            <ProjectUpdateButton disabled={busy} />
            <NotificationBell />
            <ErrorsSummaryButton />
            <button
              className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
              onClick={logout}
            >
              <LogOut className="h-4 w-4" />
              Выйти
            </button>'''
if btn_new.strip() not in t:
    t = t.replace(btn_old, btn_new, 1)

# ComponentSettingsModal enhancements
if 'refresh_lists' not in t:
    t = t.replace(
        '''                <p className="text-xs text-muted-foreground">
                  RU-direct списков: {String(settings.ru_direct_count ?? "?")}. Полное обновление: olc-update
                </p>''',
        '''                <p className="text-xs text-muted-foreground">
                  RU-direct списков: {String(settings.ru_direct_count ?? "?")}
                </p>
                <button
                  type="button"
                  className="rounded border border-border px-2 py-1 text-xs hover:bg-muted"
                  disabled={saving}
                  onClick={async () => {
                    setSaving(true);
                    setMsg("");
                    try {
                      const res = await fetch(`/api/settings/${apiName}`, {
                        method: "PUT",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ ...settings, refresh_lists: true }),
                      });
                      if (!res.ok) throw new Error(`HTTP ${res.status}`);
                      setMsg("Обновление списков запущено в фоне");
                    } catch (e) {
                      setMsg(e instanceof Error ? e.message : String(e));
                    } finally {
                      setSaving(false);
                    }
                  }}
                >
                  Обновить списки split (фон)
                </button>''',
        1,
    )

if 'exit_nodes' not in t.split('feature === "tor"')[1][:800]:
    t = t.replace(
        '''            {feature === "tor" && (
              <>
                <p className="text-xs text-muted-foreground">SOCKS порт: {String(settings.socks_port ?? "9050")}</p>
                <p className="text-xs text-muted-foreground">ExitNodes: {String(settings.exit_nodes ?? "—")}</p>
                <p className="text-xs text-muted-foreground">
                  Смена torrc — через olc-update / вручную /etc/tor/torrc (перезапуск инстансов).
                </p>
              </>
            )}''',
        '''            {feature === "tor" && (
              <>
                <p className="text-xs text-muted-foreground">SOCKS порт: {String(settings.socks_port ?? "9050")}</p>
                <label className="grid gap-1 text-muted-foreground">
                  ExitNodes (torrc)
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.exit_nodes ?? "")}
                    onChange={(e) => setStr("exit_nodes", e.target.value)}
                    placeholder="{de},{nl},{fi}"
                  />
                </label>
                <p className="text-xs text-amber-400">После сохранения — configure-tor-exit; перезапуск инстансов может понадобиться.</p>
              </>
            )}''',
        1,
    )

# fix useCapabilities export caps
if 'deploy_profile' not in t.split('function useCapabilities')[1].split('function ')[0]:
    pass

uc = t.split('function useCapabilities()')[1].split('function ')[0]
if 'caps' not in uc or 'return { visible' in uc and 'caps' not in uc.split('return')[1].split('}')[0]:
    t = t.replace(
        '  return { visible, flags: caps?.components ?? null };',
        '  return { visible, caps, flags: caps?.components ?? null };',
        1,
    ) if 'return { visible, flags' in t else t.replace(
        '  return { visible };',
        '  return { visible, caps };',
        1,
    )

p.write_text(t)
print("[patch-phase456-ui] ok"); raise SystemExit(0)
PY
