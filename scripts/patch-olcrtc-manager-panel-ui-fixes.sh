#!/usr/bin/env bash
# UI fixes: dedupe accidental duplicate declarations from legacy patches.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
orig = t

AUTODETECT_JSX = '<MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />'

# Legacy JSX still references removed component after ui-v7 migration.
t = t.replace('<NotificationSettingsSection />', AUTODETECT_JSX)
t = t.replace('<MainSettingsAutodetectLink />', AUTODETECT_JSX)
t = t.replace(
    '''            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
            </section>''',
    '            ' + AUTODETECT_JSX,
    1,
)

# Keep the inline expandable component; drop legacy no-props duplicate from ui-v7.
if 'function MainSettingsAutodetectLink({' in t:
    t = re.sub(
        r'\nfunction MainSettingsAutodetectLink\(\) \{\n(?:.*\n)*?\}\n',
        '\n',
        t,
        count=1,
    )
elif '<MainSettingsAutodetectLink' in t and 'function MainSettingsAutodetectLink' not in t:
    MAIN_SETTINGS_AUTODETECT_LINK = '''
function MainSettingsAutodetectLink() {
  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Автодетектор</div>
      <p className="text-xs text-muted-foreground">Периодически ищет ошибки в логах и состоянии сервисов.</p>
      <button
        type="button"
        className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted"
        onClick={() => window.dispatchEvent(new CustomEvent("olc-open-autodetect-settings"))}
      >
        Настройки уведомлений автодетектора
      </button>
    </section>
  );
}
'''
    t = t.replace('function NotificationBell()', MAIN_SETTINGS_AUTODETECT_LINK + '\nfunction NotificationBell()', 1)

# Collapse duplicate JSX blocks (multiline + single-line from stacked v7/v8 patches).
def dedupe_autodetect_settings_jsx(src: str) -> str:
    """Вставлять autodetect только в модалку «Настройки», не в QR и не во весь файл."""
    canon = '\n            ' + AUTODETECT_JSX + '\n'
    pwd = '<div className="text-sm font-medium text-foreground">Пароль администратора</div>'
    settings_anchor = '{showSettings && (\n        <Modal title="Настройки"'
    idx_settings = src.find(settings_anchor)
    idx_pwd = src.find(pwd, idx_settings if idx_settings >= 0 else 0)
    if idx_settings < 0 or idx_pwd < 0 or idx_pwd <= idx_settings:
        return src
    before = src[:idx_settings]
    mid = src[idx_settings:idx_pwd]
    tail = src[idx_pwd:]
    mid = re.sub(r'\s*<MainSettingsAutodetectLink[\s\S]*?/>', '', mid)
    save_row = '                Сохранить настройки\n              </button>\n            </div>'
    insert_at = mid.find(save_row)
    if insert_at < 0:
        return src
    insert_at += len(save_row)
    mid = mid[:insert_at] + canon + mid[insert_at:]
    mid = re.sub(r'\n{4,}', '\n\n\n', mid)
    return before + mid + tail

t = dedupe_autodetect_settings_jsx(t)

# Drop duplicate MainSettingsAutodetectLink with props (keep first function).
t = re.sub(
    r'(function MainSettingsAutodetectLink\(\{[\s\S]*?\n\}\n)(?:\n*function MainSettingsAutodetectLink\(\{[\s\S]*?\n\}\n)+',
    r'\1',
    t,
    count=1,
)

# Keep a single prefsOpen declaration in NotificationBell.
t = t.replace(
    '  const [prefsOpen, setPrefsOpen] = useState(false);\n  const [prefsOpen, setPrefsOpen] = useState(false);\n',
    '  const [prefsOpen, setPrefsOpen] = useState(false);\n',
    1,
)

# Dedupe duplicate olcrtc hints (legacy patch stacking).
t = re.sub(
    r'(?:^\s*olcrtc: \{[^}]+\},?\n)+',
    '  olcrtc: {\n    title: "OlcRTC",\n    lines: ["panel.env, Jitsi TLS, публичный URL", "ветка fix/all"],\n  },\n',
    t,
    count=1,
    flags=re.M,
)
t = t.replace(
    '  const [showAutodetectInline, setShowAutodetectInline] = useState(false);\n  const [showAutodetectInline, setShowAutodetectInline] = useState(false);\n',
    '  const [showAutodetectInline, setShowAutodetectInline] = useState(false);\n',
    1,
)
# Normalize accidental multiline join("\n") corruption in JSX.
t = re.sub(
    r'activeJobLines\.slice\(-250\)\.join\("\s*\n\s*"\)',
    'activeJobLines.slice(-250).join("\\\\n")',
    t,
)
t = t.replace('activeJobLines.slice(-250).join("\\n")', 'activeJobLines.slice(-250).join("\\\\n")')

# Dedupe stacked disabled= on pool refresh button (legacy v7 re-apply).
t = re.sub(
    r'(disabled=\{poolBusy \|\| jobStatus === "running"\}\s*)+',
    'disabled={poolBusy || jobStatus === "running"} ',
    t,
)

if t != orig:
    p.write_text(t)
    print("[patch-panel-ui-fixes] applied")
else:
    print("[patch-panel-ui-fixes] no changes")
PY
