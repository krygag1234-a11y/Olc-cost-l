#!/usr/bin/env bash
# Extend settings modal fields: zapret auto_sync, tor exclude exits, split panel hosts.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'panel-settings-v2' "$MAIN_TSX" && { echo "[patch-panel-settings-forms-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# panel-settings-v2
dup = '  const setBool = (key: string, value: boolean) => setSettings((s) => ({ ...s, [key]: value }));\n' * 2
single = '  const setBool = (key: string, value: boolean) => setSettings((s) => ({ ...s, [key]: value }));\n'
t = t.replace(dup, single)
if single not in t:
    t = t.replace(
        '  const setStr = (key: string, value: string) => setSettings((s) => ({ ...s, [key]: value }));\n',
        '  const setStr = (key: string, value: string) => setSettings((s) => ({ ...s, [key]: value }));\n' + single,
        1,
    )

t = t.replace(
    '''            {feature === "zapret" && (
              <>
                <label className="grid gap-1 text-muted-foreground">
                  Домены-исключения (direct, по строке)''',
    '''            {feature === "zapret" && (
              <>
                <label className="flex items-center gap-2 text-xs text-muted-foreground">
                  <input
                    type="checkbox"
                    checked={Boolean(settings.auto_sync)}
                    onChange={(e) => setBool("auto_sync", e.target.checked)}
                  />
                  Еженедельный auto-sync exclude списков
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Домены-исключения (direct, по строке)''',
    1,
)

t = t.replace(
    '''            {feature === "tor" && (
              <>
                <p className="text-xs text-muted-foreground">SOCKS порт: {String(settings.socks_port ?? "9050")}</p>
                <p className="text-xs text-muted-foreground">ExitNodes: {String(settings.exit_nodes ?? "—")}</p>
                <p className="text-xs text-muted-foreground">
                  Смена torrc — через olc-update / вручную /etc/tor/torrc (перезапуск инстансов).
                </p>
              </>
            )}''',
    '''            {feature === "tor" && (
              <>
                <p className="text-xs text-muted-foreground">SOCKS порт: {String(settings.socks_port ?? "9050")}</p>
                <label className="grid gap-1 text-muted-foreground">
                  ExitNodes
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.exit_nodes ?? "")}
                    onChange={(e) => setStr("exit_nodes", e.target.value)}
                    placeholder="{de},{nl},{fi}"
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  ExcludeExitNodes
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.exclude_exit_nodes ?? "")}
                    onChange={(e) => setStr("exclude_exit_nodes", e.target.value)}
                    placeholder="{ru},{by},{ua}"
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  После сохранения применяется configure-tor-exit (может потребоваться перезапуск инстансов).
                </p>
              </>
            )}''',
    1,
)

t = t.replace(
    '''                <p className="text-xs text-muted-foreground">
                  RU-direct списков: {String(settings.ru_direct_count ?? "?")}. Полное обновление: olc-update
                </p>''',
    '''                <label className="grid gap-1 text-muted-foreground">
                  Список panel/carrier hosts
                  <textarea
                    className="min-h-[80px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.panel_hosts ?? "")}
                    onChange={(e) => setStr("panel_hosts", e.target.value)}
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  RU-direct списков: {String(settings.ru_direct_count ?? "?")}. Полное обновление: olc-update
                </p>''',
    1,
)

p.write_text(t)
print("[patch-panel-settings-forms-v2] ok")
PY
