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

# Drop legacy duplicate MainSettingsAutodetectLink without props.
t = re.sub(
    r'\nfunction MainSettingsAutodetectLink\(\) \{\n(?:.*\n)*?\}\n(?=\nfunction NotificationBell\(\))',
    '\n',
    t,
    count=1,
)
# Drop duplicate MainSettingsAutodetectLink with props (keep first).
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
