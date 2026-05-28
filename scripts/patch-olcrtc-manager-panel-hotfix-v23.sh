#!/usr/bin/env bash
# Hotfix v23: QR modal без автодетектора; убрать сломанный AutodetectNotificationSettingsModal.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v23' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v23] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# 1) Убрать MainSettingsAutodetectLink из модалки QR (баг ui-fixes: rfind </button>).
qr_leak = re.compile(
    r'(\{qrTarget && \(\s*<Modal title=\{`QR \$\{qrTarget\.clientID\}`\}[\s\S]*?Копировать Sub\s*</button>\s*)\s*<MainSettingsAutodetectLink[^/]*/>\s*',
    re.M,
)
t, n_qr = qr_leak.subn(r'\1', t, count=1)

# 2) Сломанная ссылка на удалённый компонент (ui-v7 добавил, ui-v8 удалил функцию).
broken_jsx = re.compile(
    r'\s*\{autodetectSettingsOpen && <AutodetectNotificationSettingsModal onClose=\{\(\) => setAutodetectSettingsOpen\(false\)\} />\}\n?',
)
t, n_jsx = broken_jsx.subn('\n', t)

# 3) Заменить на рабочий mini-modal (как hotfix v3), если ещё нет.
if 'autodetectMiniOpen && <NotificationPreferencesModal' not in t:
    t = t.replace(
        '      {showSettings && (',
        '      {autodetectMiniOpen && <NotificationPreferencesModal onClose={() => setAutodetectMiniOpen(false)} />}\n      {showSettings && (',
        1,
    )

if 'const [autodetectMiniOpen, setAutodetectMiniOpen]' not in t:
    anchor = '  const [showAutodetectInline, setShowAutodetectInline] = useState(false);\n'
    if anchor in t:
        t = t.replace(
            anchor,
            anchor + '  const [autodetectMiniOpen, setAutodetectMiniOpen] = useState(false);\n',
            1,
        )

# 4) Алиас на случай если JSX остался где-то ещё.
if 'function AutodetectNotificationSettingsModal' not in t and 'AutodetectNotificationSettingsModal' in t:
    alias = '''
function AutodetectNotificationSettingsModal({ onClose }: { onClose: () => void }) {
  return <NotificationPreferencesModal onClose={onClose} />;
}

'''
    if 'function NotificationPreferencesModal' in t:
        t = t.replace('function NotificationPreferencesModal', alias + 'function NotificationPreferencesModal', 1)

# 5) Дубликат секции автодетектора в настройках (v5 + v6).
dup_section = re.compile(
    r'\{/\* autodetect-settings-inline-v6 \*/\}\s*<section className="grid gap-3 rounded-md border border-border bg-background p-4">[\s\S]*?Настройки уведомлений автодетектора[\s\S]*?</section>\s*',
)
t, n_dup = dup_section.subn('', t, count=1)

if "olc-panel-hotfix-v23" not in t:
    if "olc-panel-hotfix-v22" in t:
        t = t.replace("/* olc-panel-hotfix-v22 */", "/* olc-panel-hotfix-v22 */\n/* olc-panel-hotfix-v23 */", 1)
    else:
        t = "/* olc-panel-hotfix-v23 */\n" + t

p.write_text(t)
print(f"[patch-panel-hotfix-v23] ok (qr={n_qr}, broken_jsx={n_jsx}, dup={n_dup})"); print(0); raise SystemExit(0)
PY
