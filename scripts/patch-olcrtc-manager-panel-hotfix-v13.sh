#!/usr/bin/env bash
# Hotfix v13: WARP settings in ComponentSettingsModal, fix log newlines, bridges poll.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v13' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v13] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Literal \n in logs (bad escape from v12 patch).
t = t.replace('.join("\\\\n")', '.join("\\n")')

# WARP settings block (missing after FeatureSettingsModal -> ComponentSettingsModal refactor).
warp_anchor = '''            {feature === "webtunnel" && (
              <BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const raw = await res.text(); let body: { settings?: Record<string, unknown> } = {}; try { body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown> }; } catch { body = {}; } setSettings(body.settings ?? {}); }} />
            )}'''

warp_block = '''            {feature === "warp" && (
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
            )}
            {feature === "webtunnel" && (
              <BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const raw = await res.text(); let body: { settings?: Record<string, unknown> } = {}; try { body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown> }; } catch { body = {}; } setSettings(body.settings ?? {}); }} />
            )}'''

if '{feature === "warp"' not in t and warp_anchor in t:
    t = t.replace(warp_anchor, warp_block, 1)

# Poll bridges settings while webtunnel modal is open.
bridges_poll = '''
  useEffect(() => {
    if (feature !== "webtunnel") return;
    const poll = async () => {
      try {
        const res = await fetch("/api/settings/bridges", { cache: "no-store" });
        if (!res.ok) return;
        const raw = await res.text();
        let body: { settings?: Record<string, unknown> } = {};
        try {
          body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown> };
        } catch {
          return;
        }
        setSettings(body.settings ?? {});
      } catch {
        /* ignore */
      }
    };
    const id = window.setInterval(() => void poll(), 2500);
    return () => window.clearInterval(id);
  }, [feature]);

'''

if 'feature !== "webtunnel") return' not in t or 'void poll(), 2500' not in t:
    anchor = "  }, [apiName]);\n\n  const save = async () => {"
    if anchor in t and bridges_poll.strip() not in t:
        t = t.replace(anchor, "  }, [apiName]);\n" + bridges_poll + "\n  const save = async () => {", 1)

# Persist component drawer active job across modal close (session).
if "olc-component-job-session" not in t:
    t = t.replace(
        "function ComponentsDrawerButton() {",
        """function ComponentsDrawerButton() {
  const jobSessionKey = "olc-component-job-session";
""",
        1,
    )
    restore = """
  useEffect(() => {
    try {
      const raw = sessionStorage.getItem(jobSessionKey);
      if (!raw) return;
      const st = JSON.parse(raw) as { id?: string; lines?: string[]; msg?: string };
      if (st.id) setActiveJobId(st.id);
      if (st.lines?.length) setActiveJobLines(st.lines);
      if (st.msg) setJobMsg(st.msg);
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    if (!activeJobId && !activeJobLines.length && !jobMsg) {
      sessionStorage.removeItem(jobSessionKey);
      return;
    }
    sessionStorage.setItem(
      jobSessionKey,
      JSON.stringify({ id: activeJobId, lines: activeJobLines, msg: jobMsg }),
    );
  }, [activeJobId, activeJobLines, jobMsg]);

"""
    anchor = "  const run = async (name: string, action: \"install\" | \"uninstall\") => {"
    if anchor in t and "jobSessionKey" in t and restore.strip() not in t:
        t = t.replace(anchor, restore + anchor, 1)

if "/* olc-panel-hotfix-v12 */" in t:
    t = t.replace("/* olc-panel-hotfix-v12 */", "/* olc-panel-hotfix-v12 */\n/* olc-panel-hotfix-v13 */", 1)
else:
    t = "/* olc-panel-hotfix-v13 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v13] ok")
PY
