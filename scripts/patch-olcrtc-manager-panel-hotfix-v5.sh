#!/usr/bin/env bash
# Hotfix v5: dedicated autodetect modal from Errors + settings layout cleanup.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# 0) Guard against stale/injected global refs crashing UI.
if "olc-autoselect-shim-v5" not in t:
    shim = """
/* olc-autoselect-shim-v5 */
if (typeof window !== "undefined") {
  const w = window as unknown as Record<string, unknown>;
  if (typeof w.autoSelectLabelFn !== "function") {
    w.autoSelectLabelFn = (v: unknown) => String(v ?? "");
  }
  if (typeof w.autoSelectLabel !== "function") {
    w.autoSelectLabel = (v: unknown) => String(v ?? "");
  }
}

"""
    if "const REQUEST_TIMEOUT_MS = 15000;\n" in t:
        t = t.replace("const REQUEST_TIMEOUT_MS = 15000;\n", "const REQUEST_TIMEOUT_MS = 15000;\n" + shim, 1)
    elif "type FeatureName =" in t:
        t = t.replace("type FeatureName =", shim + "type FeatureName =", 1)
    else:
        t = shim + t

# 1) Errors button should open dedicated autodetect modal (not notification prefs).
if "const [autodetectOpen, setAutodetectOpen] = useState(false);" not in t[t.find("function ErrorsSummaryButton()"):t.find("function UpdateAvailableToast()")]:
    t = t.replace(
        "function ErrorsSummaryButton() {\n  const [open, setOpen] = useState(false);\n  const [items, setItems] = useState<PanelNotification[]>([]);\n",
        "function ErrorsSummaryButton() {\n  const [open, setOpen] = useState(false);\n  const [autodetectOpen, setAutodetectOpen] = useState(false);\n  const [items, setItems] = useState<PanelNotification[]>([]);\n",
        1,
    )

t = t.replace(
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}',
    'onClick={() => { setOpen(false); setAutodetectOpen(true); }}',
)

if "{autodetectOpen && (" not in t[t.find("function ErrorsSummaryButton()"):t.find("function UpdateAvailableToast()")]:
    t = t.replace(
        "      {open && (\n        <Modal title=\"Ошибки\" onClose={() => setOpen(false)}>",
        "      {open && (\n        <Modal title=\"Ошибки\" onClose={() => setOpen(false)}>",
        1,
    )
    t = t.replace(
        "      )}\n    </>\n  );\n}\n\n\nfunction UpdateAvailableToast() {",
        "      )}\n      {autodetectOpen && (\n        <Modal title=\"Автодетектор\" onClose={() => setAutodetectOpen(false)}>\n          <div className=\"max-h-[70vh] overflow-auto p-4\">\n            <AutodetectNotificationSettingsPanel onClose={() => setAutodetectOpen(false)} />\n          </div>\n        </Modal>\n      )}\n    </>\n  );\n}\n\n\nfunction UpdateAvailableToast() {",
        1,
    )

# 2) Move MainSettingsAutodetectLink below action buttons row.
button_block = """            <div className="flex justify-end gap-2">
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


            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />


            </div>
"""
if button_block in t:
    t = t.replace(
        button_block,
        """            <div className="flex justify-end gap-2">
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

            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
""",
        1,
    )

# Remove known empty spacer section created by older patches.
t = t.replace(
    """            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
            </section>
""",
    "",
)

# If usage was removed by previous patches, reinsert after settings buttons row.
if 'MainSettingsAutodetectLink expanded={showAutodetectInline}' not in t:
    anchor = """            <div className="flex justify-end gap-2">
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
"""
    if anchor in t:
        t = t.replace(
            anchor,
            anchor + '\n            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />\n',
            1,
        )

# Fallback: inject autodetect block right before admin password section.
if "/* autodetect-settings-inline-v5 */" not in t:
    pw_anchor = """            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">Пароль администратора</div>
"""
    inject = """
            {/* autodetect-settings-inline-v5 */}
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
    if pw_anchor in t:
        t = t.replace(pw_anchor, inject + "\n" + pw_anchor, 1)

if "olc-panel-hotfix-v5" not in t:
    marker = "/* olc-panel-hotfix-v4 */"
    if marker in t:
        t = t.replace(marker, marker + "\n/* olc-panel-hotfix-v5 */", 1)
    else:
        t = "/* olc-panel-hotfix-v5 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v5] ok"); raise SystemExit(0)
PY
#!/usr/bin/env bash
# Hotfix v5: dedicated autodetect mini-panel from Errors + settings layout cleanup.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# 1) ErrorsSummaryButton: open dedicated autodetect modal, not notification settings flow.
t = t.replace(
    'function ErrorsSummaryButton() {\n  const [open, setOpen] = useState(false);\n  const [items, setItems] = useState<PanelNotification[]>([]);\n',
    'function ErrorsSummaryButton() {\n  const [open, setOpen] = useState(false);\n  const [autodetectOpen, setAutodetectOpen] = useState(false);\n  const [items, setItems] = useState<PanelNotification[]>([]);\n',
    1,
)
t = t.replace(
    '              <button type="button" className="text-primary underline" onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}>\n                Настройки автодетектора\n              </button>',
    '              <button type="button" className="text-primary underline" onClick={() => { setAutodetectOpen(true); setOpen(false); }}>\n                Настройки автодетектора\n              </button>',
    1,
)
t = t.replace(
    '      {open && (\n        <Modal title="Ошибки" onClose={() => setOpen(false)}>',
    '      {open && (\n        <Modal title="Ошибки" onClose={() => setOpen(false)}>',
    1,
)
t = t.replace(
    '      )}\n    </>\n  );\n}\n',
    '      )}\n      {autodetectOpen && (\n        <Modal title="Автодетектор" onClose={() => setAutodetectOpen(false)}>\n          <div className="p-4">\n            <AutodetectNotificationSettingsPanel />\n          </div>\n        </Modal>\n      )}\n    </>\n  );\n}\n',
    1,
)

# 2) Settings layout: move MainSettingsAutodetectLink below action buttons.
old_block = '''            <div className="flex justify-end gap-2">
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


            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />


            </div>
'''
new_block = '''            <div className="flex justify-end gap-2">
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

            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
'''
if old_block in t:
    t = t.replace(old_block, new_block, 1)
else:
    # fallback: remove inline occurrence inside button row then inject after it
    t = t.replace(
        '            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />\n',
        '',
        1,
    )
    t = t.replace(
        '            </div>\n\n\n            <section className="grid gap-3 rounded-md border border-border bg-background p-4">',
        '            </div>\n\n            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />\n\n            <section className="grid gap-3 rounded-md border border-border bg-background p-4">',
        1,
    )

if "olc-panel-hotfix-v5" not in t:
    marker = "/* olc-panel-hotfix-v4 */"
    if marker in t:
        t = t.replace(marker, marker + "\n/* olc-panel-hotfix-v5 */", 1)
    else:
        t = "/* olc-panel-hotfix-v5 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v5] ok"); raise SystemExit(0)
PY
