#!/usr/bin/env bash
# Hotfix v3: autodetect mini-panel fallback + zapret UI cleanup.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# 1) Ensure errors button always emits mini panel event.
t = t.replace(
    'onClick={() => { setOpen(false); window.dispatchEvent(new Event("olc-open-autodetect-settings")); }}',
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}',
)
t = t.replace(
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-settings")); setOpen(false); }}',
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}',
)

# 2) Global fallback in App: open mini modal directly.
app_start = t.find("function App()")
if app_start != -1 and 'const [autodetectMiniOpen, setAutodetectMiniOpen]' not in t[app_start:app_start+12000]:
    init_anchor = "  const [showAutodetectInline, setShowAutodetectInline] = useState(false);\n"
    init_insert = "  const [autodetectMiniOpen, setAutodetectMiniOpen] = useState(false);\n"
    if init_anchor in t:
        t = t.replace(init_anchor, init_anchor + init_insert, 1)

    effect_anchor = '  useEffect(() => {\n    const onOpenAutodetect = () => {\n      setShowSettings(true);\n      setShowAutodetectInline(true);\n      void loadSettings().catch((err) => setNotice(err instanceof Error ? err.message : String(err)));\n    };\n    window.addEventListener("olc-open-autodetect-settings", onOpenAutodetect);\n    return () => window.removeEventListener("olc-open-autodetect-settings", onOpenAutodetect);\n  }, []);\n'
    add_effect = '''
  useEffect(() => {
    const onOpenMini = () => {
      setAutodetectMiniOpen(true);
    };
    window.addEventListener("olc-open-autodetect-mini", onOpenMini);
    return () => window.removeEventListener("olc-open-autodetect-mini", onOpenMini);
  }, []);
'''
    if effect_anchor in t and add_effect not in t:
        t = t.replace(effect_anchor, effect_anchor + add_effect, 1)

    render_anchor = "      {showSettings && (\n"
    render_insert = "      {autodetectMiniOpen && <NotificationPreferencesModal onClose={() => setAutodetectMiniOpen(false)} />}\n"
    if render_anchor in t and render_insert not in t:
        t = t.replace(render_anchor, render_insert + render_anchor, 1)

# 3) Deduplicate repeated zapret "community lists" lines and improve wording.
target = 'Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}'
while t.count(target) > 1:
    t = t.replace(
        '                <p className="text-xs text-muted-foreground">\n                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}\n                </p>\n',
        "",
        1,
    )
if target not in t:
    insert_after = '                <p className="text-xs text-muted-foreground">\n                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · hostlist: {String(settings.hostlist_user ?? "—")}\n                </p>\n'
    insert_block = '                <p className="text-xs text-muted-foreground">\n                  Community lists: {settings.community_sync ? "включены" : "выключены"}\n                </p>\n'
    if insert_after in t:
        t = t.replace(insert_after, insert_after + insert_block, 1)
else:
    t = t.replace(target, 'Community lists: {settings.community_sync ? "включены" : "выключены"}', 1)

# Make strategy lines clearer.
t = t.replace(
    '                  Текущая: {String(settings.strategy_current ?? settings.strategy ?? "—")}\n',
    '                  Активная стратегия: {String(settings.strategy_current ?? settings.strategy ?? "—")}\n',
)
t = t.replace(
    '                  Стратегия zapret\n',
    '                  Выбор стратегии Zapret\n',
)

if "olc-panel-hotfix-v3" not in t:
    marker_from = "/* olc-panel-hotfix-v2 */"
    marker_to = "/* olc-panel-hotfix-v2 */\n/* olc-panel-hotfix-v3 */"
    if marker_from in t:
        t = t.replace(marker_from, marker_to, 1)
    else:
        t = "/* olc-panel-hotfix-v3 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v3] ok")
PY
