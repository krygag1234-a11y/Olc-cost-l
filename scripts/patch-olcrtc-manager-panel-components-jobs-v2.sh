#!/usr/bin/env bash
# Components drawer: persistent job statuses + inline logs.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -Fq 'jobsByComponent, setJobsByComponent' "$MAIN_TSX" && { echo "[patch-panel-components-jobs-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

new_fn = r'''function ComponentsDrawerButton() {
  const [open, setOpen] = useState(false);
  const { caps } = useCapabilities();
  const [jobMsg, setJobMsg] = useState("");
  const [jobsByComponent, setJobsByComponent] = useState<Record<string, { job_id?: string; status?: string; action?: string; error?: string }>>({});
  const [activeJobId, setActiveJobId] = useState<string | null>(null);
  const [activeJobLines, setActiveJobLines] = useState<string[]>([]);

  const loadJobs = async () => {
    try {
      const res = await fetch("/api/components/jobs", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as { jobs?: { component?: string; job_id?: string; status?: string; action?: string; error?: string }[] };
      const next: Record<string, { job_id?: string; status?: string; action?: string; error?: string }> = {};
      for (const j of body.jobs ?? []) {
        if (!j.component || next[j.component]) continue;
        next[j.component] = { job_id: j.job_id, status: j.status, action: j.action, error: j.error };
      }
      setJobsByComponent(next);
    } catch {
      // ignore
    }
  };

  const loadJobLog = async (jobId: string) => {
    try {
      const lr = await fetch(`/api/jobs/${encodeURIComponent(jobId)}/log`, { cache: "no-store" });
      if (!lr.ok) return;
      const body = (await lr.json()) as { lines?: string[] };
      setActiveJobLines(body.lines ?? []);
    } catch {
      // ignore
    }
  };

  useEffect(() => {
    if (!open) return;
    void loadJobs();
    const id = window.setInterval(() => void loadJobs(), 4000);
    return () => window.clearInterval(id);
  }, [open]);

  useEffect(() => {
    if (!activeJobId) return;
    void loadJobLog(activeJobId);
    const id = window.setInterval(() => void loadJobLog(activeJobId), 2500);
    return () => window.clearInterval(id);
  }, [activeJobId]);

  const run = async (name: string, action: "install" | "uninstall") => {
    const word = action === "install" ? "установить" : "отключить";
    if (!window.confirm(`${word} ${name}? Может занять несколько минут.`)) return;
    setJobMsg("Запуск…");
    try {
      const res = await fetch(`/api/components/${name}/${action}`, { method: "POST" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
      const jobId = (body as { job_id?: string }).job_id ?? "";
      setJobMsg(`Задача ${jobId} запущена`);
      setJobsByComponent((prev) => ({ ...prev, [name]: { job_id: jobId, status: "running", action } }));
      if (jobId) {
        setActiveJobId(jobId);
      }
      await loadJobs();
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
              const j = jobsByComponent[c.id];
              const isRunning = j?.status === "running";
              const statusText = j
                ? j.status === "running"
                  ? `${j.action === "uninstall" ? "Отключается" : "Устанавливается"}…`
                  : j.status === "done"
                    ? "Последняя задача: выполнено"
                    : j.status === "failed"
                      ? `Ошибка: ${j.error ?? "см. лог"}`
                      : `Статус: ${j.status ?? "unknown"}`
                : "";
              return (
                <div key={c.id} className="flex flex-wrap items-center justify-between gap-2 rounded border border-border p-2">
                  <div>
                    <div className="font-medium">{c.label}</div>
                    <div className="text-xs text-muted-foreground">
                      {installed ? "установлен" : "не установлен"}
                      {st?.enabled ? " · вкл" : st?.installed ? " · выкл" : ""}
                    </div>
                    {statusText && <div className={`text-xs ${j?.status === "failed" ? "text-destructive" : "text-amber-400"}`}>{statusText}</div>}
                  </div>
                  <div className="flex gap-2">
                    {j?.job_id && (
                      <button
                        type="button"
                        className="rounded border border-border px-2 py-1 text-xs"
                        onClick={() => setActiveJobId(j.job_id ?? null)}
                      >
                        Лог
                      </button>
                    )}
                    {!installed && (
                      <button
                        type="button"
                        className="rounded border border-primary px-2 py-1 text-xs text-primary"
                        disabled={isRunning}
                        onClick={() => void run(c.id, "install")}
                      >
                        {isRunning ? "Устанавливается…" : "Установить"}
                      </button>
                    )}
                    {installed && (
                      <button
                        type="button"
                        className="rounded border border-destructive px-2 py-1 text-xs text-destructive"
                        disabled={isRunning}
                        onClick={() => void run(c.id, "uninstall")}
                      >
                        {isRunning ? "Выполняется…" : "Отключить"}
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
            {jobMsg && <p className="text-xs text-muted-foreground">{jobMsg}</p>}
            {activeJobId && (
              <div className="rounded border border-border bg-background p-2">
                <div className="mb-2 flex items-center justify-between">
                  <div className="text-xs text-muted-foreground">Лог задачи: {activeJobId}</div>
                  <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => setActiveJobId(null)}>
                    Закрыть
                  </button>
                </div>
                <pre className="max-h-48 overflow-auto text-xs">{activeJobLines.slice(-250).join("\n")}</pre>
              </div>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}
'''

t2 = re.sub(
    r'function ComponentsDrawerButton\(\) \{[\s\S]*?\n\}\n\nfunction ErrorsSummaryButton\(\) \{',
    lambda _m: new_fn + '\n\nfunction ErrorsSummaryButton() {',
    t,
    count=1,
)
if t2 == t:
    print("[patch-panel-components-jobs-v2] no changes"); raise SystemExit(0)
    raise SystemExit(0)
p.write_text(t2)
print("[patch-panel-components-jobs-v2] ok"); raise SystemExit(0)
PY
