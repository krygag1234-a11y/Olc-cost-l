#!/usr/bin/env bash
# Auto-hide completed component job status/log after ~2 minutes.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
if grep -q 'function componentJobUiVisible' "$MAIN_TSX"; then
  echo "[patch-panel-components-jobs-ui-ttl] already applied"
  exit 0
fi
grep -q 'jobsByComponent, setJobsByComponent' "$MAIN_TSX" || { echo "[patch-panel-components-jobs-ui-ttl] need jobs v2"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

const_block = '''
const COMPONENT_JOB_UI_TTL_MS = 120_000;

function componentJobFinishedMs(j?: { finished_at?: string; status?: string }): number | null {
  if (!j?.finished_at) return null;
  const ms = Date.parse(j.finished_at);
  return Number.isFinite(ms) ? ms : null;
}

function componentJobUiVisible(j?: { status?: string; finished_at?: string }): boolean {
  if (!j?.status) return false;
  if (j.status === "running") return true;
  if (j.status === "failed") {
    const doneAt = componentJobFinishedMs(j);
    return doneAt == null || Date.now() - doneAt < COMPONENT_JOB_UI_TTL_MS * 2;
  }
  if (j.status === "done") {
    const doneAt = componentJobFinishedMs(j);
    return doneAt == null || Date.now() - doneAt < COMPONENT_JOB_UI_TTL_MS;
  }
  return false;
}
'''

if "COMPONENT_JOB_UI_TTL_MS" not in t:
    t = t.replace(
        "const COMPONENT_DRAWER_ITEMS = [",
        const_block + "\nconst COMPONENT_DRAWER_ITEMS = [",
        1,
    )

t = t.replace(
    "const [jobsByComponent, setJobsByComponent] = useState<Record<string, { job_id?: string; status?: string; action?: string; error?: string }>>({});",
    "const [jobsByComponent, setJobsByComponent] = useState<Record<string, { job_id?: string; status?: string; action?: string; error?: string; finished_at?: string }>>({});",
    1,
)

t = t.replace(
    "const body = (await res.json()) as { jobs?: { component?: string; job_id?: string; status?: string; action?: string; error?: string }[] };",
    "const body = (await res.json()) as { jobs?: { component?: string; job_id?: string; status?: string; action?: string; error?: string; finished_at?: string }[] };",
    1,
)

t = t.replace(
    "const next: Record<string, { job_id?: string; status?: string; action?: string; error?: string }> = {};",
    "const next: Record<string, { job_id?: string; status?: string; action?: string; error?: string; finished_at?: string }> = {};",
    1,
)

t = t.replace(
    "next[j.component] = { job_id: j.job_id, status: j.status, action: j.action, error: j.error };",
    "if (!componentJobUiVisible(j)) continue;\n        next[j.component] = { job_id: j.job_id, status: j.status, action: j.action, error: j.error, finished_at: j.finished_at };",
    1,
)

# Auto-close log panel shortly after job completes
auto_close = '''
  useEffect(() => {
    if (!activeJobId) return;
    const entry = Object.values(jobsByComponent).find((j) => j.job_id === activeJobId);
    if (!entry || entry.status === "running") return;
    const doneAt = componentJobFinishedMs(entry) ?? Date.now();
    const left = COMPONENT_JOB_UI_TTL_MS - (Date.now() - doneAt);
    const delay = Math.max(0, Math.min(left, COMPONENT_JOB_UI_TTL_MS));
    const timer = window.setTimeout(() => {
      setActiveJobId(null);
      setActiveJobLines([]);
      setJobMsg("");
    }, delay);
    return () => window.clearTimeout(timer);
  }, [activeJobId, jobsByComponent]);

  useEffect(() => {
    if (!open) return;
    const timer = window.setInterval(() => {
      setJobsByComponent((prev) => {
        const next: typeof prev = {};
        for (const [k, j] of Object.entries(prev)) {
          if (componentJobUiVisible(j)) next[k] = j;
        }
        return Object.keys(next).length === Object.keys(prev).length ? prev : next;
      });
    }, 15_000);
    return () => window.clearInterval(timer);
  }, [open]);
'''

if "COMPONENT_JOB_UI_TTL_MS - (Date.now() - doneAt)" not in t:
    t = t.replace(
        "  useEffect(() => {\n    if (!activeJobId) return;\n    void loadJobLog(activeJobId);",
        auto_close + "\n  useEffect(() => {\n    if (!activeJobId) return;\n    void loadJobLog(activeJobId);",
        1,
    )

t = t.replace(
    '''              const statusText = j
                ? j.status === "running"
                  ? `${j.action === "uninstall" ? "Отключается" : "Устанавливается"}…`
                  : j.status === "done"
                    ? "Последняя задача: выполнено"
                    : j.status === "failed"
                      ? `Ошибка: ${j.error ?? "см. лог"}`
                      : `Статус: ${j.status ?? "unknown"}`
                : "";''',
    '''              const showJob = j && componentJobUiVisible(j);
              const statusText = showJob
                ? j.status === "running"
                  ? `${j.action === "uninstall" ? "Отключается" : "Устанавливается"}…`
                  : j.status === "done"
                    ? "Готово"
                    : j.status === "failed"
                      ? `Ошибка: ${j.error ?? "см. лог"}`
                      : `Статус: ${j.status ?? "unknown"}`
                : "";''',
    1,
)

t = t.replace(
    "{j?.job_id && (",
    "{j?.job_id && showJob && (",
    1,
)

if "/* olc-components-jobs-ui-ttl */" not in t:
    t = t.replace("/* olc-panel-components-jobs-v2 */", "/* olc-panel-components-jobs-v2 */\n/* olc-components-jobs-ui-ttl */", 1)
    if "/* olc-components-jobs-ui-ttl */" not in t:
        t = t.replace("function ComponentsDrawerButton() {", "/* olc-components-jobs-ui-ttl */\nfunction ComponentsDrawerButton() {", 1)

p.write_text(t)
print("[patch-panel-components-jobs-ui-ttl] ok")
PY
