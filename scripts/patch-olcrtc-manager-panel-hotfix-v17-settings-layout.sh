#!/usr/bin/env bash
# Fix settings modal: autodetect section was inserted inside unclosed button row (v12 regression).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v17-settings-layout' "$MAIN_TSX" && exit 0

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

needle = """            <div className="flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => { setShowAutodetectInline(false); setShowSettings(false); }}
              >
                Закрыть
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={saveSettings}
              >
                <Settings className="h-4 w-4" />
                Сохранить настройки
              </button>


            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
              {showAutodetectInline && (
                <div className="rounded-md border border-dashed border-border bg-card p-3">
                  <AutodetectNotificationSettingsPanel />
                </div>
              )}
            </section>

            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">Пароль администратора</div>"""

fixed = """            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
              {showAutodetectInline && (
                <div className="rounded-md border border-dashed border-border bg-card p-3">
                  <AutodetectNotificationSettingsPanel />
                </div>
              )}
            </section>

            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">Пароль администратора</div>"""

if needle not in t:
    print("[patch-v17-settings-layout] pattern not found (skip)")
    sys.exit(0)

t = t.replace(needle, fixed, 1)

footer = """              </div>
            </section>
          </div>
        </Modal>
      )}

      {clientLogTarget && ("""

footer_fixed = """              </div>
            </section>

            <div className="flex justify-end gap-2">
              <button
                className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80"
                onClick={() => { setShowAutodetectInline(false); setShowSettings(false); }}
              >
                Закрыть
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={saveSettings}
              >
                <Settings className="h-4 w-4" />
                Сохранить настройки
              </button>
            </div>
          </div>
        </Modal>
      )}

      {clientLogTarget && ("""

if footer not in t:
    print("[patch-v17-settings-layout] footer not found (skip)")
    sys.exit(0)
t = t.replace(footer, footer_fixed, 1)

if "olc-panel-hotfix-v17-settings-layout" not in t:
    t = t.replace("/* olc-panel-hotfix-v17 */", "/* olc-panel-hotfix-v17 */\n/* olc-panel-hotfix-v17-settings-layout */", 1)

p.write_text(t)
print("[patch-v17-settings-layout] ok")
PY
