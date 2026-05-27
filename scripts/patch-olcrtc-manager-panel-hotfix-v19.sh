#!/usr/bin/env bash
# Hotfix v19: robust top header alignment + component drawer button state fix.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v19' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v19] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old_pat = re.compile(r'<header className="border-b border-border bg-background/95">[\s\S]*?</header>', re.M)
new_header = '''<header className="border-b border-border bg-background/95">
        <div className="mx-auto max-w-7xl px-5 py-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold tracking-normal">OlcRTC Manager</h1>
            <div className="flex flex-wrap items-center gap-2">
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={openSettings}
              >
                <Settings className="h-4 w-4" />
                Настройки
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
                disabled={busy}
                onClick={() =>
                  runAction(async () => {
                    await loadState();
                    await loadMetrics();
                  }, "Обновлено")
                }
              >
                <RefreshCw className="h-4 w-4" />
                Обновить
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={logout}
              >
                <LogOut className="h-4 w-4" />
                Выйти
              </button>
            </div>
          </div>
          <div className="mt-2 grid gap-2 xl:grid-cols-[1fr_auto_1fr] xl:items-center">
            <div className="flex flex-wrap items-center gap-2 xl:justify-start">
              <ComponentsDrawerButton />
              <HeaderMetric label="Panel mem" value={formatBytes(metrics?.memory.heap_alloc_bytes)} />
              <HeaderMetric label="Servers mem" value={formatBytes(serversMemoryBytes)} />
              <HeaderMetric label="Panel PID" value={metrics?.manager.pid ?? "..."} />
            </div>
            <div className="flex min-h-9 min-w-0 items-center justify-start xl:justify-center">
              <HeaderNetworkToggles />
            </div>
            <div className="flex flex-wrap items-center gap-2 xl:justify-end">
              <ProjectUpdateButton disabled={busy} />
              <NotificationBell />
              <ErrorsSummaryButton />
            </div>
          </div>
        </div>
      </header>'''

m = old_pat.search(t)
if m:
    t = t[:m.start()] + new_header + t[m.end():]

t = t.replace('{!installed && (', '{showInstallBtn && (', 1)
t = t.replace('{installed && (', '{showDeleteBtn && (', 1)

status_old = '{statusText && <div className={`text-xs ${j?.status === "failed" ? "text-destructive" : "text-amber-400"}`}>{statusText}</div>}'
status_new = '{statusText && <div className={`text-xs ${j?.status === "failed" ? "text-destructive" : j?.status === "done" ? "text-emerald-400" : "text-amber-400"}`}>{statusText}</div>}'
if status_old in t:
    t = t.replace(status_old, status_new, 1)

if "olc-panel-hotfix-v19" not in t:
    if "/* olc-panel-hotfix-v18 */" in t:
        t = t.replace("/* olc-panel-hotfix-v18 */", "/* olc-panel-hotfix-v18 */\n/* olc-panel-hotfix-v19 */", 1)
    elif "/* olc-panel-hotfix-v17 */" in t:
        t = t.replace("/* olc-panel-hotfix-v17 */", "/* olc-panel-hotfix-v17 */\n/* olc-panel-hotfix-v19 */", 1)
    else:
        t = "/* olc-panel-hotfix-v19 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v19] ok")
PY
