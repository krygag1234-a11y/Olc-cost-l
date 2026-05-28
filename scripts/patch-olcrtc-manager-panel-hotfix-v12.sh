#!/usr/bin/env bash
# Hotfix v12: autodetect dedupe, component jobMsg TTL, bridges pool log panel.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Remove duplicate autodetect block; fix section wrapper around MainSettingsAutodetectLink.
dup = """            {/* autodetect-settings-inline-v6 */}
            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">Автодетектор</div>
              <p className="text-xs text-muted-foreground">Периодически ищет ошибки в логах и состоянии сервисов.</p>
              <button type="button" className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted" onClick={() => setShowAutodetectInline((v) => !v)}>
                Настройки уведомлений автодетектора
              </button>


"""
if dup in t:
    t = t.replace(dup, "", 1)

broken = """            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
              {showAutodetectInline && (
                <div className="rounded-md border border-dashed border-border bg-card p-3">
                  <AutodetectNotificationSettingsPanel />
                </div>
              )}
            </section>"""
fixed = """            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
              {showAutodetectInline && (
                <div className="rounded-md border border-dashed border-border bg-card p-3">
                  <AutodetectNotificationSettingsPanel />
                </div>
              )}
            </section>"""
if broken in t:
    t = t.replace(broken, fixed, 1)

# Components drawer: clear jobMsg on close; TTL success message.
if "JOB_MSG_TTL_MS" not in t:
    t = t.replace(
        "const COMPONENT_JOB_UI_TTL_MS = 120_000;",
        "const COMPONENT_JOB_UI_TTL_MS = 120_000;\nconst JOB_MSG_TTL_MS = 45_000;",
        1,
    )

old_modal_close = '<Modal title="Компоненты VPS" onClose={() => setOpen(false)}>'
new_modal_close = '<Modal title="Компоненты VPS" onClose={() => { setOpen(false); setJobMsg(""); setActiveJobId(null); setActiveJobLines([]); }}>'
if old_modal_close in t:
    t = t.replace(old_modal_close, new_modal_close, 1)

old_log_close = """                  <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => setActiveJobId(null)}>
                    Закрыть
                  </button>"""
new_log_close = """                  <button type="button" className="text-xs text-muted-foreground hover:text-foreground" onClick={() => { setActiveJobId(null); setActiveJobLines([]); if (jobMsg === "Установлено" || jobMsg === "Удалено") setJobMsg(""); }}>
                    Закрыть
                  </button>"""
if old_log_close in t:
    t = t.replace(old_log_close, new_log_close, 1)

if "jobMsg === \"Установлено\"" not in t[t.find("function ComponentsDrawerButton"):t.find("function ErrorsSummaryButton")]:
    inject = """
  useEffect(() => {
    if (!jobMsg || (jobMsg !== "Установлено" && jobMsg !== "Удалено")) return;
    const timer = window.setTimeout(() => setJobMsg(""), JOB_MSG_TTL_MS);
    return () => window.clearTimeout(timer);
  }, [jobMsg]);

"""
    anchor = "  const run = async (name: string, action: \"install\" | \"uninstall\") => {"
    if anchor in t:
        t = t.replace(anchor, inject + anchor, 1)

# Bridges pool: show log_tail, poll while modal open when job active, webtunnel_client from pool_job.
bridges_old = """  useEffect(() => {
    if (jobStatus !== "running") return;
    const id = window.setInterval(() => void onReload(), 2500);
    return () => window.clearInterval(id);
  }, [jobStatus, onReload]);"""

bridges_new = """  const logTail = (poolJob.log_tail as string[]) ?? [];
  const wtInstalled = Boolean(poolJob.webtunnel_client ?? settings.webtunnel_client);

  useEffect(() => {
    if (jobStatus !== "running" && jobStatus !== "done" && jobStatus !== "error") return;
    const id = window.setInterval(() => void onReload(), 2500);
    return () => window.clearInterval(id);
  }, [jobStatus, onReload]);

  useEffect(() => {
    if (jobStatus !== "done" && jobStatus !== "error") return;
    const timer = window.setTimeout(() => void onReload(), JOB_MSG_TTL_MS);
    return () => window.clearTimeout(timer);
  }, [jobStatus]);"""

if bridges_old in t and "logTail" not in t:
    t = t.replace(bridges_old, bridges_new, 1)

wt_warn_old = "{settings.webtunnel === false && String(sys.types ?? \"\").includes(\"webtunnel\")"
wt_warn_new = "{!wtInstalled && String(sys.types ?? \"\").includes(\"webtunnel\")"
if wt_warn_old in t:
    t = t.replace(wt_warn_old, wt_warn_new, 1)

status_block_old = """      {jobStatus === "done" && poolJob.finished_at && (
        <p className="text-xs text-emerald-400">Готово {String(poolJob.finished_at).slice(11, 19)}</p>
      )}"""
status_block_new = r"""      {jobStatus === "done" && poolJob.finished_at && (
        <p className="text-xs text-emerald-400">Готово {String(poolJob.finished_at).slice(11, 19)} · webtunnel-client: {wtInstalled ? "да" : "нет"}</p>
      )}
      {(jobStatus === "running" || jobStatus === "done" || jobStatus === "error") && logTail.length > 0 && (
        <details open={jobStatus === "running"} className="rounded border border-border bg-background p-2">
          <summary className="cursor-pointer text-xs text-muted-foreground">Лог обновления пула</summary>
          <pre className="mt-2 max-h-48 overflow-auto text-[10px] leading-relaxed">{logTail.join("\n")}</pre>
        </details>
      )}"""
if status_block_old in t and "Лог обновления пула" not in t:
    t = t.replace(status_block_old, status_block_new, 1)

# Poll bridges settings when bridges modal is open (parent passes onReload).
if "function ComponentSettingsModal" in t and "bridgesPoll" not in t:
    t = t.replace(
        "  useEffect(() => {\n    let cancelled = false;\n    (async () => {\n      try {\n        const res = await fetch(`/api/settings/${apiName}`, { cache: \"no-store\" });",
        "  useEffect(() => {\n    if (feature !== \"bridges\") return;\n    const id = window.setInterval(() => {\n      void (async () => {\n        try {\n          const res = await fetch(`/api/settings/bridges`, { cache: \"no-store\" });\n          if (!res.ok) return;\n          const body = (await res.json()) as { settings?: Record<string, unknown> };\n          setSettings(body.settings ?? {});\n        } catch { /* ignore */ }\n      })();\n    }, 3000);\n    return () => window.clearInterval(id);\n  }, [feature]);\n\n  useEffect(() => {\n    let cancelled = false;\n    (async () => {\n      try {\n        const res = await fetch(`/api/settings/${apiName}`, { cache: \"no-store\" });",
        1,
    )

if "olc-panel-hotfix-v12" not in t:
    if "/* olc-panel-hotfix-v11 */" in t:
        t = t.replace("/* olc-panel-hotfix-v11 */", "/* olc-panel-hotfix-v11 */\n/* olc-panel-hotfix-v12 */", 1)
    else:
        t = "/* olc-panel-hotfix-v12 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v12] ok"); print(0); raise SystemExit(0)
PY
