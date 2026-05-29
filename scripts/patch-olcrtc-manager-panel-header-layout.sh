#!/usr/bin/env bash
# Header toolbar: aligned rows (title/actions, then metrics | network | project tools).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-header-layout-v1' "$MAIN_TSX" && { echo "[patch-panel-header-layout] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if '/* olc-header-layout-v1 */' not in t:
    t = t.replace('/* olc-project-ui-fix */', '/* olc-project-ui-fix */\n/* olc-header-layout-v1 */', 1)

old_header = '''      <header className="border-b border-border bg-background/95">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-5 py-4">
          <div>
            <h1 className="text-2xl font-semibold tracking-normal">OlcRTC Manager</h1>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <ComponentsDrawerButton />
            <HeaderMetric label="Panel mem" value={formatBytes(metrics?.memory.heap_alloc_bytes)} />
            <HeaderMetric label="Servers mem" value={formatBytes(serversMemoryBytes)} />
            <HeaderMetric label="Panel PID" value={metrics?.manager.pid ?? "..."} />
            <HeaderNetworkToggles />
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
            <ProjectUpdateButton disabled={busy} />
            <NotificationBell />
            <ErrorsSummaryButton />
            <button
              className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
              onClick={logout}
            >
              <LogOut className="h-4 w-4" />
              Выйти
            </button>
          </div>
        </div>
      </header>'''

new_header = '''      <header className="border-b border-border bg-background/95">
        <div className="mx-auto max-w-7xl space-y-3 px-5 py-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="text-2xl font-semibold tracking-normal">OlcRTC Manager</h1>
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                className="inline-flex h-9 shrink-0 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={openSettings}
              >
                <Settings className="h-4 w-4" />
                Настройки
              </button>
              <button
                type="button"
                className="inline-flex h-9 shrink-0 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
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
                type="button"
                className="inline-flex h-9 shrink-0 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={logout}
              >
                <LogOut className="h-4 w-4" />
                Выйти
              </button>
            </div>
          </div>
          <div className="flex flex-col gap-3 xl:flex-row xl:items-center xl:gap-4">
            <div className="flex flex-wrap items-center gap-2">
              <ComponentsDrawerButton />
              <HeaderMetric label="Panel mem" value={formatBytes(metrics?.memory.heap_alloc_bytes)} />
              <HeaderMetric label="Servers mem" value={formatBytes(serversMemoryBytes)} />
              <HeaderMetric label="Panel PID" value={metrics?.manager.pid ?? "..."} />
            </div>
            <div className="flex min-h-9 min-w-0 flex-1 items-center xl:justify-center">
              <HeaderNetworkToggles />
            </div>
            <div className="flex flex-wrap items-center gap-2 xl:shrink-0 xl:justify-end">
              <ProjectUpdateButton disabled={busy} />
              <NotificationBell />
              <ErrorsSummaryButton />
            </div>
          </div>
        </div>
      </header>'''

if old_header not in t:
    print("[patch-panel-header-layout] header block not found", file=sys.stderr); raise SystemExit(0)
    sys.exit(1)
t = t.replace(old_header, new_header, 1)

# HeaderNetworkToggles: single flex row, err below (no stray span breaking alignment).
old_ret = '''  return (
    <>
      <div className="flex flex-wrap items-center gap-2 rounded-md border border-border bg-muted/40 px-2 py-1">'''
new_ret = '''  return (
    <div className="flex w-full min-w-0 flex-col gap-1">
      <div className="flex flex-wrap items-center gap-2 rounded-md border border-border bg-muted/40 px-2 py-1">'''
if old_ret in t:
    t = t.replace(old_ret, new_ret, 1)
    t = t.replace(
        '''      {settingsFeature && <FeatureSettingsModal feature={settingsFeature} onClose={() => setSettingsFeature(null)} />}
    </>
  );
}''',
        '''      {settingsFeature && <FeatureSettingsModal feature={settingsFeature} onClose={() => setSettingsFeature(null)} />}
    </div>
  );
}''',
        1,
    )
    t = t.replace(
        '{err && <span className="max-w-xs truncate text-xs text-red-400" title={err}>{err}</span>}',
        '{err && <p className="max-w-full truncate text-xs text-red-400" title={err}>{err}</p>}',
        1,
    )

p.write_text(t)
print("[patch-panel-header-layout] ok"); raise SystemExit(0)
PY
