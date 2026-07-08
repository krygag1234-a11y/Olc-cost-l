#!/usr/bin/env bash
# Small UX polish:
#  1. Remove the log-source path label(s) from the addon log modal
#     (FeatureLogsModal showed it twice: "/var/log/olcrtc-...").
#  2. Persist the main settings modal open-state to localStorage so a page
#     reload keeps the settings modal open where the user left it.
# Idempotent. Target: manager src/main.tsx. Run late (after autologi-ui).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-logs-polish] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-logs-polish] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-logs-polish] {label}: ok")
    else:
        print(f"[patch-logs-polish] WARN {label}: anchor not found")

# --- 1a. Remove path in the header row (keep the flex container spacing) ---
repl(
    '          {path && <div className="text-xs text-muted-foreground truncate">{path}</div>}\n',
    '',
    "remove header path label",
)

# --- 1b. Remove the second path line above the log box ---
repl(
    '        {path && <div className="mb-2 text-xs text-muted-foreground">{path}</div>}\n',
    '',
    "remove second path label",
)

# --- 2. Persist main settings modal open-state across reload ---
repl(
    '  const [showSettings, setShowSettings] = useState(false);',
    '  const [showSettings, setShowSettings] = useState(() => readStoredBool("olc-settings-open-v1", false));',
    "settings-open init from storage",
    guard='olc-settings-open-v1',
)
# openSettings: persist true
repl(
    '''  const openSettings = async () => {
    setShowSettings(true);
    setShowAutodetectInline(false);
    setNotice("");''',
    '''  const openSettings = async () => {
    setShowSettings(true);
    writeStoredBool("olc-settings-open-v1", true);
    setShowAutodetectInline(false);
    setNotice("");''',
    "openSettings persist true",
    guard='writeStoredBool("olc-settings-open-v1", true);',
)
# close handlers: persist false (both close paths)
repl(
    "        <Modal wide title={t('settings')} onClose={() => setShowSettings(false)}>",
    "        <Modal wide title={t('settings')} onClose={() => { setShowSettings(false); writeStoredBool(\"olc-settings-open-v1\", false); }}>",
    "settings modal onClose persist false",
)
repl(
    'onClick={() => { setShowAutodetectInline(false); setShowSettings(false); }}',
    'onClick={() => { setShowAutodetectInline(false); setShowSettings(false); writeStoredBool("olc-settings-open-v1", false); }}',
    "settings footer close persist false",
)
# When restored open on reload, load its data on mount.
repl(
    '    Promise.all([loadState(), loadSettings(), loadMetrics(), loadAudit(), fetchInstanceDefaultsFromAPI()]).catch((err) =>',
    '    if (readStoredBool("olc-settings-open-v1", false)) { loadSettings().catch(() => {}); }\n    Promise.all([loadState(), loadSettings(), loadMetrics(), loadAudit(), fetchInstanceDefaultsFromAPI()]).catch((err) =>',
    "load settings on mount if restored open",
    guard='if (readStoredBool("olc-settings-open-v1", false)) { loadSettings()',
)

if changed:
    f.write_text(t)
print("[patch-logs-polish] ok")
PY
