#!/usr/bin/env bash
# Hotfix v4: component drawer UX constraints + autodetect mini-only open.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Ensure errors button explicitly opens mini autodetect panel.
t = t.replace(
    'onClick={() => { setOpen(false); window.dispatchEvent(new Event("olc-open-autodetect-settings")); }}',
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}',
)
t = t.replace(
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-settings")); setOpen(false); }}',
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}',
)

# Components drawer: do not allow enabling bridges if tor is off.
old = "              const installed = st?.installed ?? false;\n              const j = jobsByComponent[c.id];\n              const isRunning = j?.status === \"running\";\n              const showJob = j && componentJobUiVisible(j);\n"
new = "              const installed = st?.installed ?? false;\n              const enabled = Boolean(st?.enabled);\n              const torEnabled = Boolean(caps?.components?.tor?.enabled);\n              const canInstall = c.id === \"bridges\" ? torEnabled : true;\n              const j = jobsByComponent[c.id];\n              const isRunning = j?.status === \"running\";\n              const showJob = j && componentJobUiVisible(j);\n"
if old in t:
    t = t.replace(old, new, 1)

t = t.replace(
    '                        disabled={isRunning}\n                        onClick={() => void run(c.id, "install")}',
    '                        disabled={isRunning || !canInstall}\n                        title={!canInstall ? "Сначала включите Tor" : undefined}\n                        onClick={() => void run(c.id, "install")}',
    1,
)

# Hide WARP from network/feature rows when not installed in caps.
t = t.replace(
    "  const visible = (name: FeatureName) => {\n    const key = name === \"webtunnel\" ? \"bridges\" : name === \"warp\" ? \"warp\" : name;\n    const c = caps?.components?.[key];\n    if (!c) return true;\n    return c.installed !== false;\n  };\n",
    "  const visible = (name: FeatureName) => {\n    const key = name === \"webtunnel\" ? \"bridges\" : name === \"warp\" ? \"warp\" : name;\n    const c = caps?.components?.[key];\n    if (!c) return name !== \"warp\";\n    if (key === \"warp\") return c.installed === true;\n    return c.installed !== false;\n  };\n",
    1,
)

# Header mini toggles: block bridges enable when Tor is off.
t = t.replace(
    '          const splitBlocked = it.name === "split" && !flags?.tor;\n          const warpBlocked = it.name === "warp" && Boolean(flags?.tor);\n          const torBlocked = it.name === "tor" && Boolean(flags?.warp);\n          const blocked = splitBlocked || warpBlocked || torBlocked;\n',
    '          const splitBlocked = it.name === "split" && !flags?.tor;\n          const bridgesBlocked = it.name === "webtunnel" && !flags?.tor;\n          const warpBlocked = it.name === "warp" && Boolean(flags?.tor);\n          const torBlocked = it.name === "tor" && Boolean(flags?.warp);\n          const blocked = splitBlocked || bridgesBlocked || warpBlocked || torBlocked;\n',
    1,
)
t = t.replace(
    '              : splitBlocked\n                ? "Сначала Tor"\n                : `${it.name}: ${on ? "on" : "off"}`;',
    '              : splitBlocked || bridgesBlocked\n                ? "Сначала Tor"\n                : `${it.name}: ${on ? "on" : "off"}`;',
    1,
)

if "olc-panel-hotfix-v4" not in t:
    marker = "/* olc-panel-hotfix-v3 */"
    if marker in t:
        t = t.replace(marker, marker + "\n/* olc-panel-hotfix-v4 */", 1)
    else:
        t = "/* olc-panel-hotfix-v4 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v4] ok")
PY
