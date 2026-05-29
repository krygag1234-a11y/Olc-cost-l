#!/usr/bin/env bash
# Logs UI: add "show detailed" toggle for per-instance and per-client logs.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-logs-verbose-v1' "$MAIN_TSX" && { echo "[patch-panel-logs-verbose-v1] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "const [logsVerbose, setLogsVerbose] = useState(false);" not in t:
    t = t.replace(
        "  const [logs, setLogs] = useState<LogLine[]>([]);\n",
        "  const [logs, setLogs] = useState<LogLine[]>([]);\n  const [logsVerbose, setLogsVerbose] = useState(false);\n",
        1,
    )

client_old = """                    ) : (
                      group.lines.map((line, index) => (
                        <div key={`${line.time}-${index}`} className="whitespace-pre-wrap break-words">
                          <span className={line.stream === "stderr" ? "text-destructive" : "text-primary"}>
                            {line.stream}
                          </span>{" "}
                          <span className="text-muted-foreground">{line.time}</span> {line.line}
                        </div>
                      ))
                    )}
"""
client_new = """                    ) : (
                      group.lines.map((line, index) => (
                        <div key={`${line.time}-${index}`} className="whitespace-pre-wrap break-words">
                          {logsVerbose ? (
                            <>
                              <span className={line.stream === "stderr" ? "text-destructive" : "text-primary"}>
                                {line.stream}
                              </span>{" "}
                              <span className="text-muted-foreground">{line.time}</span> {line.line}
                            </>
                          ) : (
                            line.line
                          )}
                        </div>
                      ))
                    )}
"""
if client_old in t:
    t = t.replace(client_old, client_new, 1)

single_old = """              ) : (
                logs.map((line, index) => (
                  <div key={`${line.time}-${index}`} className="whitespace-pre-wrap break-words">
                    <span className={line.stream === "stderr" ? "text-destructive" : "text-primary"}>
                      {line.stream}
                    </span>{" "}
                    <span className="text-muted-foreground">{line.time}</span> {line.line}
                  </div>
                ))
              )}
"""
single_new = """              ) : (
                logs.map((line, index) => (
                  <div key={`${line.time}-${index}`} className="whitespace-pre-wrap break-words">
                    {logsVerbose ? (
                      <>
                        <span className={line.stream === "stderr" ? "text-destructive" : "text-primary"}>
                          {line.stream}
                        </span>{" "}
                        <span className="text-muted-foreground">{line.time}</span> {line.line}
                      </>
                    ) : (
                      line.line
                    )}
                  </div>
                ))
              )}
"""
if single_old in t:
    t = t.replace(single_old, single_new, 1)

footer_old = """            <div className="mt-5 flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => openClientLogs(clientLogTarget)}
              >
                Обновить
              </button>
            </div>
"""
footer_new = """            <div className="mt-5 flex items-center justify-between gap-2">
              <label className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                <input type="checkbox" checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
                Показать подробно (time/stream)
              </label>
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => openClientLogs(clientLogTarget)}
              >
                Обновить
              </button>
            </div>
"""
if footer_old in t:
    t = t.replace(footer_old, footer_new, 1)

footer2_old = """            <div className="mt-5 flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => openLogs(logTarget.clientID, logTarget.location)}
              >
                Обновить
              </button>
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
                disabled={logs.length === 0 || busy}
                onClick={copyLogs}
              >
                Копировать
              </button>
            </div>
"""
footer2_new = """            <div className="mt-5 flex items-center justify-between gap-2">
              <label className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                <input type="checkbox" checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
                Показать подробно (time/stream)
              </label>
              <div className="flex justify-end gap-2">
                <button
                  className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                  onClick={() => openLogs(logTarget.clientID, logTarget.location)}
                >
                  Обновить
                </button>
                <button
                  className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
                  disabled={logs.length === 0 || busy}
                  onClick={copyLogs}
                >
                  Копировать
                </button>
              </div>
            </div>
"""
if footer2_old in t:
    t = t.replace(footer2_old, footer2_new, 1)

if "olc-panel-logs-verbose-v1" not in t:
    t = t.replace("/* olc-panel-ui-v10 */", "/* olc-panel-ui-v10 */\n/* olc-panel-logs-verbose-v1 */", 1)

p.write_text(t)
print("[patch-panel-logs-verbose-v1] ok"); raise SystemExit(0)
PY
