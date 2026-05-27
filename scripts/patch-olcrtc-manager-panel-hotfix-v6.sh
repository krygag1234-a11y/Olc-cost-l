#!/usr/bin/env bash
# Hotfix v6: safe autodetect modal wiring without risky global shims.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# 1) Errors modal -> dedicated autodetect modal.
if "const [autodetectOpen, setAutodetectOpen] = useState(false);" not in t:
    t = t.replace(
        "function ErrorsSummaryButton() {\n  const [open, setOpen] = useState(false);\n  const [items, setItems] = useState<PanelNotification[]>([]);\n",
        "function ErrorsSummaryButton() {\n  const [open, setOpen] = useState(false);\n  const [autodetectOpen, setAutodetectOpen] = useState(false);\n  const [items, setItems] = useState<PanelNotification[]>([]);\n",
        1,
    )
t = t.replace(
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}',
    'onClick={() => { setOpen(false); setAutodetectOpen(true); }}',
)
t = t.replace(
    "      )}\n    </>\n  );\n}\n\n\nfunction UpdateAvailableToast() {",
    "      )}\n      {autodetectOpen && (\n        <Modal title=\"Автодетектор\" onClose={() => setAutodetectOpen(false)}>\n          <div className=\"max-h-[70vh] overflow-auto p-4\">\n            <AutodetectNotificationSettingsPanel onClose={() => setAutodetectOpen(false)} />\n          </div>\n        </Modal>\n      )}\n    </>\n  );\n}\n\n\nfunction UpdateAvailableToast() {",
    1,
)

# 2) Settings layout: put autodetect section below buttons before password section.
if "autodetect-settings-inline-v6" not in t:
    password_anchor = """            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">Пароль администратора</div>
"""
    block = """
            {/* autodetect-settings-inline-v6 */}
            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">Автодетектор</div>
              <p className="text-xs text-muted-foreground">Периодически ищет ошибки в логах и состоянии сервисов.</p>
              <button type="button" className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted" onClick={() => setShowAutodetectInline((v) => !v)}>
                Настройки уведомлений автодетектора
              </button>
              {showAutodetectInline && (
                <div className="rounded-md border border-dashed border-border bg-card p-3">
                  <AutodetectNotificationSettingsPanel />
                </div>
              )}
            </section>
"""
    if password_anchor in t:
        t = t.replace(password_anchor, block + "\n" + password_anchor, 1)

if "olc-panel-hotfix-v6" not in t:
    marker = "/* olc-panel-hotfix-v4 */"
    if marker in t:
        t = t.replace(marker, marker + "\n/* olc-panel-hotfix-v6 */", 1)
    else:
        t = "/* olc-panel-hotfix-v6 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v6] ok")
PY
