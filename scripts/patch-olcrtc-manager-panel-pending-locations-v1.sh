#!/usr/bin/env bash
# Ensure pendingLocations useState lives in App(), not LoginView (ui-v3 bug).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()
marker = "/* olc-pending-locations-v1 */"
changed = False

pending_line = "  const [pendingLocations, setPendingLocations] = useState<Record<string, string>>({});\n"

login_start = t.find("function LoginView")
app_start = t.find("function App() {")
if login_start >= 0 and app_start > login_start:
    login_section = t[login_start:app_start]
    if pending_line in login_section:
        t = t[:login_start] + login_section.replace(pending_line, "", 1) + t[app_start:]
        changed = True

app_start = t.find("function App() {")
if app_start >= 0:
    app_end = t.find("\nfunction ", app_start + 12)
    if app_end < 0:
        app_end = len(t)
    app_section = t[app_start:app_end]

    uses_pending = (
        "setPendingLocations" in app_section
        or "pendingLocations[locationActionKey" in app_section
    )
    has_state = "const [pendingLocations, setPendingLocations]" in app_section

    if uses_pending and not has_state:
        busy_line = "  const [busy, setBusy] = useState(false);"
        idx = app_section.find(busy_line)
        if idx >= 0:
            insert_at = app_start + idx + len(busy_line)
            insert = f"\n{pending_line.rstrip()}\n  {marker}"
            t = t[:insert_at] + insert + t[insert_at:]
            changed = True

if marker not in t and not changed:
    print("[patch-panel-pending-locations-v1] skip (nothing to fix)")
    sys.exit(0)

if marker not in t and changed:
    pass  # marker inserted with state

p.write_text(t)
print("[patch-panel-pending-locations-v1] ok")
PY
