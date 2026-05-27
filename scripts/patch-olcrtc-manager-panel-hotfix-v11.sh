#!/usr/bin/env bash
# Hotfix v11: component drawer buttons follow active job action (no install+delete at once).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old = """              const j = jobsByComponent[c.id];
              const isRunning = j?.status === "running";
              const showJob = j && componentJobUiVisible(j);
              const statusText = showJob"""

new = """              const j = jobsByComponent[c.id];
              const isRunning = j?.status === "running";
              const jobAction = isRunning ? j?.action : undefined;
              const showInstallBtn = jobAction === "install" || (!jobAction && !installed);
              const showDeleteBtn = jobAction === "uninstall" || (!jobAction && installed);
              const showJob = j && componentJobUiVisible(j);
              const statusText = showJob"""

if old in t and "showInstallBtn" not in t:
    t = t.replace(old, new, 1)

t = t.replace(
    """                    {!installed && (
                      <button
                        type="button"
                        className="rounded border border-primary px-2 py-1 text-xs text-primary"
                        disabled={isRunning || !canInstall}
                        title={!canInstall ? "Сначала включите Tor" : undefined}
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
                        {isRunning ? "Удаляется…" : "Удалить"}
                      </button>
                    )}""",
    """                    {showInstallBtn && (
                      <button
                        type="button"
                        className="rounded border border-primary px-2 py-1 text-xs text-primary"
                        disabled={(isRunning && jobAction !== "install") || !canInstall}
                        title={!canInstall ? "Сначала включите Tor" : undefined}
                        onClick={() => void run(c.id, "install")}
                      >
                        {jobAction === "install" ? "Устанавливается…" : "Установить"}
                      </button>
                    )}
                    {showDeleteBtn && (
                      <button
                        type="button"
                        className="rounded border border-destructive px-2 py-1 text-xs text-destructive"
                        disabled={isRunning && jobAction !== "uninstall"}
                        onClick={() => void run(c.id, "uninstall")}
                      >
                        {jobAction === "uninstall" ? "Удаляется…" : "Удалить"}
                      </button>
                    )}""",
    1,
)

if "olc-panel-hotfix-v11" not in t:
    if "/* olc-panel-hotfix-v10 */" in t:
        t = t.replace("/* olc-panel-hotfix-v10 */", "/* olc-panel-hotfix-v10 */\n/* olc-panel-hotfix-v11 */", 1)
    else:
        t = "/* olc-panel-hotfix-v11 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v11] ok")
PY
