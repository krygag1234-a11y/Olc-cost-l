#!/usr/bin/env bash
# Hotfix v18: bridges status row, stable pool log panel, no instant auto-close.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v18' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v18] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# poolUiActive: always show log when user opened it
for old, new in [
    ("const poolUiActive = poolUiOpen && bridgePoolUiVisible(poolJob);", "const poolUiActive = poolUiOpen;"),
    ("const poolUiActive = poolUiOpen && bridgePoolUiVisible(poolJob);", "const poolUiActive = poolUiOpen;"),
]:
    if old in t:
        t = t.replace(old, new, 1)
        break

# Remove auto-close timer that hides log/hint right after stale "done" jobs
auto_close = """  useEffect(() => {
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

if auto_close in t:
    t = t.replace(auto_close, "  /* olc-panel-hotfix-v18: pool log stays until user closes */", 1)

# Status badges row (webtunnel + job state) before pool stats paragraph
status_row = """      <div className="flex flex-wrap gap-2 text-xs">
        <span className="rounded border border-border bg-muted/50 px-2 py-1">
          webtunnel-client: <strong className={wtInstalled ? "text-emerald-400" : "text-amber-400"}>{wtInstalled ? "да" : "нет"}</strong>
        </span>
        <span className="rounded border border-border bg-muted/50 px-2 py-1">
          обновление пула: <strong className="text-foreground">{jobStatus === "running" ? "идёт" : jobStatus === "done" ? "готово" : jobStatus === "error" ? "ошибка" : "ожидание"}</strong>
        </span>
        {poolBusy && <span className="rounded border border-amber-500/40 bg-amber-500/10 px-2 py-1 text-amber-400">запуск…</span>}
      </div>
"""

anchor = '      <p className="text-xs text-muted-foreground">\n        Пул:'
if status_row.strip() not in t and anchor in t:
    t = t.replace(anchor, status_row + "\n" + anchor, 1)

# refreshPool: optimistic running state so UI does not flash and close
old_start = """  const refreshPool = async (types: string) => {
    setPoolBusy(true);
    setPoolUiOpen(true);
    setPoolHint("Обновление пула запущено…");
    try:"""

new_start = """  const refreshPool = async (types: string) => {
    setPoolBusy(true);
    setPoolUiOpen(true);
    setPoolHint("Обновление пула запущено…");
    setSettings((s) => ({
      ...s,
      pool_job: {
        status: "running",
        started_at: new Date().toISOString(),
        types,
        log_path: "/var/log/olcrtc-bridge-pool.log",
        log_tail: ["[ui] запуск обновления пула мостов…"],
      },
    }));
    try:"""

if old_start in t:
    t = t.replace(old_start, new_start, 1)

# Ensure log pre shows placeholder while running
t = t.replace(
    '{(logTail.length > 0 ? logTail : [jobStatus === "running" ? "Ожидание строк лога…" : ""]).slice(-250).join("\\n")}',
    '{(logTail.length > 0 ? logTail : [jobStatus === "running" ? "Ожидание строк лога…" : poolHint || ""]).slice(-250).join("\\n")}',
    1,
)

if "olc-panel-hotfix-v18" not in t:
    if "/* olc-panel-hotfix-v17 */" in t:
        t = t.replace("/* olc-panel-hotfix-v17 */", "/* olc-panel-hotfix-v17 */\n/* olc-panel-hotfix-v18 */", 1)
    elif "/* olc-panel-hotfix-v16 */" in t:
        t = t.replace("/* olc-panel-hotfix-v16 */", "/* olc-panel-hotfix-v16 */\n/* olc-panel-hotfix-v18 */", 1)
    else:
        t = "/* olc-panel-hotfix-v18 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v18] ok"); raise SystemExit(0)
PY
