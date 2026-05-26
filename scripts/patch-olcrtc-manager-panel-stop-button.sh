#!/usr/bin/env bash
# Add Stop button for location (without delete).
set -euo pipefail

MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-panel-stop] skip: $MAIN_TSX not found"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "const stopLocation = (clientID: string, location: LocationState)" in t:
    print("[patch-panel-stop] already applied")
    raise SystemExit(0)

restart_fn = """  const restartLocation = (clientID: string, location: LocationState) =>
    runAction(async () => {
      await request("/api/actions/restart", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: clientID,
          room_id: location.room_id,
          transport: location.transport,
        }),
      });
    }, `${clientID} перезапущен`);"""

stop_fn = """  const stopLocation = (clientID: string, location: LocationState) =>
    runAction(async () => {
      await request("/api/actions/stop", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: clientID,
          room_id: location.room_id,
          transport: location.transport,
        }),
      });
    }, `${clientID} остановлен`);"""

if restart_fn not in t:
    raise SystemExit("[patch-panel-stop] restart function block not found")
t = t.replace(restart_fn, restart_fn + "\n\n" + stop_fn, 1)

restart_button = """                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                                      disabled={busy}
                                      onClick={() => restartLocation(client.client_id, loc)}
                                    >
                                      <RefreshCw className="h-4 w-4" />
                                      Restart
                                    </button>"""

stop_button = """                                    <button
                                      className="inline-flex h-8 items-center gap-2 rounded-md border border-amber-500/40 px-2 text-sm text-amber-300 hover:bg-amber-500/10 disabled:opacity-60"
                                      disabled={busy || !loc.runtime.running}
                                      onClick={() => stopLocation(client.client_id, loc)}
                                    >
                                      Стоп
                                    </button>"""

if restart_button not in t:
    print("[patch-panel-stop] skip (ui-v3 already has stop)")
    raise SystemExit(0)
t = t.replace(restart_button, restart_button + "\n" + stop_button, 1)

p.write_text(t)
print("[patch-panel-stop] applied")
PY
