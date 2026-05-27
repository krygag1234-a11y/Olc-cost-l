#!/usr/bin/env bash
# Hotfix v16: bridges pool log inline (like ±), persist until job done + TTL.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v16' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v16] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helpers = '''
const BRIDGE_POOL_UI_KEY = "olc-bridge-pool-ui";

function bridgePoolFinishedMs(job?: Record<string, unknown>): number | null {
  const raw = job?.finished_at;
  if (typeof raw !== "string" || !raw) return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : null;
}

function bridgePoolUiVisible(job?: Record<string, unknown>): boolean {
  const status = String(job?.status ?? "idle");
  if (status === "running") return true;
  if (status === "done" || status === "error") {
    const doneAt = bridgePoolFinishedMs(job);
    if (doneAt == null) return true;
    return Date.now() - doneAt < JOB_MSG_TTL_MS;
  }
  return false;
}

'''

if "BRIDGE_POOL_UI_KEY" not in t:
    t = t.replace("function BridgesSettingsFields({", helpers + "function BridgesSettingsFields({", 1)

# Replace state + effects block inside BridgesSettingsFields
old_block = """  const [poolBusy, setPoolBusy] = useState(false);
  const poolJob = (settings.pool_job as Record<string, unknown>) ?? {};
  const jobStatus = String(poolJob.status ?? "idle");

  const logTail = (poolJob.log_tail as string[]) ?? [];
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

new_block = """  const [poolBusy, setPoolBusy] = useState(false);
  const [poolUiOpen, setPoolUiOpen] = useState(false);
  const [poolHint, setPoolHint] = useState("");
  const poolJob = (settings.pool_job as Record<string, unknown>) ?? {};
  const jobStatus = String(poolJob.status ?? "idle");
  const logTail = (poolJob.log_tail as string[]) ?? [];
  const wtInstalled = Boolean(poolJob.webtunnel_client ?? settings.webtunnel_client);
  const poolUiActive = poolUiOpen && bridgePoolUiVisible(poolJob);

  useEffect(() => {
    try {
      const raw = sessionStorage.getItem(BRIDGE_POOL_UI_KEY);
      if (!raw) return;
      const st = JSON.parse(raw) as { open?: boolean; hint?: string; job?: Record<string, unknown> };
      if (st.job && bridgePoolUiVisible(st.job)) {
        setPoolUiOpen(Boolean(st.open));
        if (st.hint) setPoolHint(st.hint);
      }
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    if (!poolUiOpen && !poolHint && jobStatus === "idle") {
      sessionStorage.removeItem(BRIDGE_POOL_UI_KEY);
      return;
    }
    sessionStorage.setItem(
      BRIDGE_POOL_UI_KEY,
      JSON.stringify({ open: poolUiOpen, hint: poolHint, job: poolJob }),
    );
  }, [poolUiOpen, poolHint, poolJob, jobStatus]);

  useEffect(() => {
    if (jobStatus === "running") setPoolUiOpen(true);
  }, [jobStatus]);

  useEffect(() => {
    if (!bridgePoolUiVisible(poolJob)) return;
    const ms = jobStatus === "running" ? 1500 : 4000;
    const id = window.setInterval(() => void onReload(), ms);
    return () => window.clearInterval(id);
  }, [jobStatus, poolJob, onReload]);

  useEffect(() => {
    if (jobStatus !== "done" && jobStatus !== "error") return;
    const doneAt = bridgePoolFinishedMs(poolJob) ?? Date.now();
    const left = JOB_MSG_TTL_MS - (Date.now() - doneAt);
    const delay = Math.max(0, Math.min(left, JOB_MSG_TTL_MS));
    const timer = window.setTimeout(() => {
      setPoolUiOpen(false);
      setPoolHint("");
      sessionStorage.removeItem(BRIDGE_POOL_UI_KEY);
    }, delay);
    return () => window.clearTimeout(timer);
  }, [jobStatus, poolJob]);"""

if old_block in t:
    t = t.replace(old_block, new_block, 1)
else:
    print("[patch-panel-hotfix-v16] state block not found", file=sys.stderr)
    sys.exit(1)

old_refresh = """  const refreshPool = async (types: string) => {
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
  };"""

new_refresh = """  const refreshPool = async (types: string) => {
    setPoolBusy(true);
    setPoolUiOpen(true);
    setPoolHint("Обновление пула запущено…");
    try {
      const res = await fetch("/api/settings/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "refresh_pool", types }),
      });
      const body = (await res.json()) as { pool_job?: Record<string, unknown>; error?: string };
      if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
      const pj = body.pool_job ?? { status: "running" };
      setSettings((s) => ({ ...s, pool_job: pj }));
      setPoolHint("Обновление пула…");
      await onReload();
      const poolWaitStarted = Date.now();
      while (Date.now() - poolWaitStarted < 600_000) {
        await new Promise((r) => window.setTimeout(r, 1500));
        const res2 = await fetch("/api/settings/bridges", { cache: "no-store" });
        if (!res2.ok) break;
        const raw2 = await res2.text();
        let b2: { settings?: Record<string, unknown> } = {};
        try {
          b2 = (raw2 ? JSON.parse(raw2) : {}) as { settings?: Record<string, unknown> };
        } catch {
          break;
        }
        const pj2 = (b2.settings?.pool_job as Record<string, unknown>) ?? {};
        setSettings((s) => ({ ...s, pool_job: pj2, pool_stats: b2.settings?.pool_stats ?? s.pool_stats }));
        const st = String(pj2.status ?? "");
        if (st === "done") {
          setPoolHint(`Готово ${String(pj2.finished_at ?? "").slice(11, 19)}`);
          break;
        }
        if (st === "error") {
          setPoolHint(String(pj2.error ?? "ошибка обновления"));
          break;
        }
        if (st !== "running") break;
      }
      await onReload();
    } catch (e) {
      setPoolHint(e instanceof Error ? e.message : String(e));
    } finally {
      setPoolBusy(false);
    }
  };"""

if old_refresh in t:
    t = t.replace(old_refresh, new_refresh, 1)

old_ui = """      {jobStatus === "running" && <p className="text-xs text-amber-400">Обновление пула…</p>}
      {jobStatus === "error" && <p className="text-xs text-destructive">{String(poolJob.error ?? "ошибка")}</p>}
      {jobStatus === "done" && poolJob.finished_at && (
        <p className="text-xs text-emerald-400">Готово {String(poolJob.finished_at).slice(11, 19)} · webtunnel-client: {wtInstalled ? "да" : "нет"}</p>
      )}
      {(jobStatus === "running" || jobStatus === "done" || jobStatus === "error") && logTail.length > 0 && (
        <details open={jobStatus === "running"} className="rounded border border-border bg-background p-2">
          <summary className="cursor-pointer text-xs text-muted-foreground">Лог обновления пула</summary>
          <pre className="mt-2 max-h-48 overflow-auto text-[10px] leading-relaxed">{logTail.join("\\n")}</pre>
        </details>
      )}"""

new_ui = """      {poolHint && (
        <p className={`text-xs ${jobStatus === "error" ? "text-destructive" : jobStatus === "done" ? "text-emerald-400" : "text-amber-400"}`}>
          {poolHint}
          {jobStatus === "done" && ` · webtunnel-client: ${wtInstalled ? "да" : "нет"}`}
        </p>
      )}
      {poolUiActive && (
        <div className="rounded border border-border bg-background p-2">
          <div className="mb-2 flex items-center justify-between gap-2">
            <span className="text-xs text-muted-foreground">Лог обновления пула</span>
            <button
              type="button"
              className="text-xs text-muted-foreground hover:text-foreground"
              onClick={() => {
                setPoolUiOpen(false);
                setPoolHint("");
                sessionStorage.removeItem(BRIDGE_POOL_UI_KEY);
              }}
            >
              Закрыть
            </button>
          </div>
          <pre className="max-h-48 overflow-auto text-xs leading-relaxed whitespace-pre-wrap">
            {(logTail.length > 0 ? logTail : [jobStatus === "running" ? "Ожидание строк лога…" : ""]).slice(-250).join("\\n")}
          </pre>
        </div>
      )}"""

# Fix join if file has single backslash
if old_ui not in t and "Лог обновления пула" in t:
    old_ui2 = old_ui.replace('join("\\\\n")', 'join("\\n")')
    if old_ui2 in t:
        old_ui = old_ui2
        new_ui = new_ui.replace('join("\\\\n")', 'join("\\n")')

if old_ui in t:
    t = t.replace(old_ui, new_ui, 1)
elif "poolUiActive" not in t:
    print("[patch-panel-hotfix-v16] UI block not found", file=sys.stderr)
    sys.exit(1)

# Poll bridges settings whenever webtunnel modal open (ComponentSettingsModal)
poll_old = """  useEffect(() => {
    if (feature !== "webtunnel") return;
    const poll = async () => {"""
poll_new = """  useEffect(() => {
    if (feature !== "webtunnel") return;
    const poll = async () => {"""
# ensure poll exists - if v13 already added, add faster poll when pool running - skip if complex

if "olc-panel-hotfix-v16" not in t:
    if "/* olc-panel-hotfix-v15 */" in t:
        t = t.replace("/* olc-panel-hotfix-v15 */", "/* olc-panel-hotfix-v15 */\n/* olc-panel-hotfix-v16 */", 1)
    else:
        t = "/* olc-panel-hotfix-v16 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v16] ok")
PY
