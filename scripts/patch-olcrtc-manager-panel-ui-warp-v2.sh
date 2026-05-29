#!/usr/bin/env bash
# WARP UI settings v2: mode/autoconnect/plus/license.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'tun (blocked by safety)' "$MAIN_TSX" && { echo "[patch-panel-ui-warp-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old = '''            {feature === "warp" && (
              <>
                <p className="text-xs text-amber-400">WARP и Tor взаимоисключают. На RU VPS обычно Tor; на foreign — профиль foreign-warp.</p>
                <label className="grid gap-1 text-muted-foreground">
                  WARP proxy (OLCRTC_WARP_PROXY)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.proxy ?? "127.0.0.1:40000")} onChange={(e) => setStr("proxy", e.target.value)} placeholder="127.0.0.1:40000" />
                </label>
                <p className="text-xs text-muted-foreground">
                  Установлен: {settings.installed ? "да" : "нет"} · подключён: {settings.connected ? "да" : "нет"}
                  {settings.profile_enabled ? " · в профиле VPS" : ""}
                </p>
              </>
            )}'''

new = '''            {feature === "warp" && (
              <>
                <p className="text-xs text-amber-400">WARP и Tor взаимоисключают. На RU VPS обычно Tor; на foreign — профиль foreign-warp.</p>
                <label className="grid gap-1 text-muted-foreground">
                  WARP proxy (OLCRTC_WARP_PROXY)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.proxy ?? "127.0.0.1:40000")} onChange={(e) => setStr("proxy", e.target.value)} placeholder="127.0.0.1:40000" />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Mode
                  <select
                    className="h-9 rounded-md border border-border bg-background px-2 text-xs"
                    value={String(settings.mode ?? "proxy")}
                    onChange={(e) => setStr("mode", e.target.value)}
                  >
                    <option value="proxy">proxy (safe)</option>
                    <option value="tun" disabled>tun (blocked by safety)</option>
                  </select>
                </label>
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.autoconnect ?? true)} onChange={(e) => setBool("autoconnect", e.target.checked)} />
                  Автоподключение WARP при включении компонента
                </label>
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.warp_plus)} onChange={(e) => setBool("warp_plus", e.target.checked)} />
                  Использовать WARP+ (нужен license key)
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  License key (optional)
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono"
                    value={String(settings.license_key ?? "")}
                    onChange={(e) => setStr("license_key", e.target.value)}
                    placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  Установлен: {settings.installed ? "да" : "нет"} · подключён: {settings.connected ? "да" : "нет"}
                  {settings.profile_enabled ? " · в профиле VPS" : ""}
                </p>
                <p className="text-xs text-amber-400">Безопасность: full-tunnel/TUN режим принудительно заблокирован в backend и install-скрипте, чтобы не сломать SSH.</p>
              </>
            )}'''

if old in t:
    t = t.replace(old, new, 1)

p.write_text(t)
print("[patch-panel-ui-warp-v2] ok"); raise SystemExit(0)
PY
