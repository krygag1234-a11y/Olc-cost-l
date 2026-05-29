#!/usr/bin/env bash
# Prevent panel black screen on bad API data: normalize state + ErrorBoundary.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'PanelErrorBoundary' "$MAIN_TSX" && { echo "[patch-panel-safe-state] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helpers = r'''
const defaultRuntime = (): RuntimeState => ({
  status: "unknown",
  running: false,
  log_count: 0,
  restarts: 0,
});

function normalizeLocationState(loc: Partial<LocationState>): LocationState {
  const runtime = loc.runtime ?? defaultRuntime();
  return {
    name: loc.name ?? "Default",
    room_id: loc.room_id ?? "",
    key: loc.key ?? "",
    uri: loc.uri ?? "",
    carrier: loc.carrier ?? "jitsi",
    transport: loc.transport ?? "datachannel",
    payload: loc.payload ?? {},
    link: loc.link ?? "tor",
    dns: loc.dns ?? "1.1.1.1:53",
    running: Boolean(loc.running ?? runtime.running),
    runtime: {
      ...defaultRuntime(),
      ...runtime,
      running: Boolean(runtime.running),
    },
  };
}

function normalizePanelState(raw: State): State {
  const clients = (raw.clients ?? [])
    .filter((c) => c && typeof c === "object")
    .map((c) => ({
      client_id: String(c.client_id ?? "").trim(),
      refresh: c.refresh,
      quota: c.quota ?? {},
      locations: (c.locations ?? []).map((loc) => normalizeLocationState(loc as Partial<LocationState>)),
    }))
    .filter((c) => c.client_id !== "");
  return {
    ...raw,
    clients,
    client_count: clients.length,
    port: Number(raw.port) || 8888,
  };
}

class PanelErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { error: Error | null }
> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        <div className="grid min-h-screen place-items-center p-6">
          <div className="max-w-lg rounded-lg border border-destructive/40 bg-card p-6 text-sm">
            <h2 className="text-lg font-semibold text-destructive">Ошибка панели</h2>
            <p className="mt-2 text-muted-foreground">
              Панель не смогла отобразить данные (возможно, некорректная локация в config). Обновите страницу; если не
              помогло — удалите проблемную локацию через CLI или исправьте config.json.
            </p>
            <pre className="mt-3 max-h-40 overflow-auto rounded border border-border bg-background p-2 text-xs">
              {this.state.error.message}
            </pre>
            <button
              type="button"
              className="mt-4 rounded-md border border-border bg-muted px-3 py-2 hover:bg-muted/80"
              onClick={() => window.location.reload()}
            >
              Обновить страницу
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

'''

anchor = "function formatBytes(bytes?: number)"
if "PanelErrorBoundary" not in t:
    t = t.replace(anchor, helpers + "\n" + anchor, 1)

t = t.replace(
    "    setState((await res.json()) as State);",
    "    setState(normalizePanelState((await res.json()) as State));",
    1,
)

t = t.replace(
    "  const serversMemoryBytes = metrics?.children.reduce(\n    (total, child) => total + (child.runtime.memory_bytes ?? 0),\n    0,\n  );",
    "  const serversMemoryBytes = (metrics?.children ?? []).reduce(\n    (total, child) => total + (child.runtime?.memory_bytes ?? 0),\n    0,\n  );",
    1,
)

t = t.replace(
    "const running = client.locations.filter((location) => location.runtime.running).length;",
    "const running = (client.locations ?? []).filter((location) => location.runtime?.running).length;",
    1,
)

t = t.replace(
    "loc.runtime.running ? \"bg-primary/15 text-primary\" : \"bg-destructive/15 text-destructive\"",
    "loc.runtime?.running ? \"bg-primary/15 text-primary\" : \"bg-destructive/15 text-destructive\"",
    1,
)

t = t.replace(
    "{loc.runtime.status}",
    "{loc.runtime?.status ?? \"unknown\"}",
    1,
)

t = t.replace(
    'createRoot(document.getElementById("root")!).render(<App />);',
    'createRoot(document.getElementById("root")!).render(\n  <PanelErrorBoundary>\n    <App />\n  </PanelErrorBoundary>,\n);',
    1,
)

p.write_text(t)
print("[patch-panel-safe-state] ok"); raise SystemExit(0)
PY
