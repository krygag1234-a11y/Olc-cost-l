#!/usr/bin/env bash
# Hotfix v10: refresh capabilities/features after component jobs; rename uninstall to Удалить.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# useCapabilities: reload on custom event + export reloadCaps
if "olc-capabilities-changed" not in t:
    t = t.replace(
        """    const iv = window.setInterval(() => {
      if (!cancelled) void (async () => {
        try {
          const res = await fetch("/api/capabilities", { cache: "no-store" });
          if (!res.ok) return;
          const body = (await res.json()) as Capabilities;
          if (!cancelled) setCaps(body);
        } catch { /* ignore */ }
      })();
    }, 30_000);
    return () => {
      cancelled = true;
      window.clearInterval(iv);
    };
  }, []); /* capabilitiesRefresh30s */""",
        """    const reloadCaps = async () => {
      try {
        const res = await fetch("/api/capabilities", { cache: "no-store" });
        if (!res.ok) return;
        const body = (await res.json()) as Capabilities;
        if (!cancelled) setCaps(body);
      } catch {
        /* ignore */
      }
    };
    const onCapsChanged = () => void reloadCaps();
    window.addEventListener("olc-capabilities-changed", onCapsChanged);
    const iv = window.setInterval(() => void reloadCaps(), 30_000);
    return () => {
      cancelled = true;
      window.clearInterval(iv);
      window.removeEventListener("olc-capabilities-changed", onCapsChanged);
    };
  }, []); /* capabilitiesRefresh30s */""",
        1,
    )

# ComponentsDrawerButton: poll job completion and refresh UI
if "waitForComponentJobDone" not in t:
    wait_fn = '''
async function waitForComponentJobDone(component: string, jobId: string, timeoutMs = 600_000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const res = await fetch("/api/components/jobs", { cache: "no-store" });
      if (!res.ok) break;
      const body = (await res.json()) as { jobs?: { component?: string; job_id?: string; status?: string }[] };
      const job = (body.jobs ?? []).find((j) => j.component === component && j.job_id === jobId);
      if (!job || job.status === "done" || job.status === "failed") return job?.status ?? "done";
    } catch {
      /* ignore */
    }
    await new Promise((r) => window.setTimeout(r, 2000));
  }
  return "timeout";
}

'''
    t = t.replace("const COMPONENT_DRAWER_ITEMS = [", wait_fn + "const COMPONENT_DRAWER_ITEMS = [", 1)

run_old = """      await loadJobs();
    } catch (e) {
      setJobMsg(e instanceof Error ? e.message : String(e));
    }
  };"""

run_new = """      await loadJobs();
      if (jobId) {
        const finalStatus = await waitForComponentJobDone(name, jobId);
        await loadJobs();
        window.dispatchEvent(new Event("olc-capabilities-changed"));
        window.dispatchEvent(new Event("olc-features-changed"));
        if (finalStatus === "done") {
          setJobMsg(action === "install" ? "Установлено" : "Удалено");
        } else if (finalStatus === "failed") {
          setJobMsg("Ошибка задачи — см. лог");
        }
      }
    } catch (e) {
      setJobMsg(e instanceof Error ? e.message : String(e));
    }
  };"""

if run_old in t and "waitForComponentJobDone" in t:
    t = t.replace(run_old, run_new, 1)

# Uninstall wording
t = t.replace(
    'const word = action === "install" ? "установить" : "отключить";',
    'const word = action === "install" ? "установить" : "удалить";',
)
t = t.replace(
    '{isRunning ? "Выполняется…" : "Отключить"}',
    '{isRunning ? "Удаляется…" : "Удалить"}',
)
t = t.replace(
    '${j.action === "uninstall" ? "Отключается" : "Устанавливается"}…',
    '${j.action === "uninstall" ? "Удаляется" : "Устанавливается"}…',
)

if "olc-panel-hotfix-v10" not in t:
    if "/* olc-panel-hotfix-v8 */" in t:
        t = t.replace("/* olc-panel-hotfix-v8 */", "/* olc-panel-hotfix-v8 */\n/* olc-panel-hotfix-v10 */", 1)
    else:
        t = "/* olc-panel-hotfix-v10 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v10] ok"); raise SystemExit(0)
PY
