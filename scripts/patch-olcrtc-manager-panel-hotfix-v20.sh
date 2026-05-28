#!/usr/bin/env bash
# Hotfix v20: VPS-stable panel fixes (2026-05-27 test VPS)
# - JOB_MSG_TTL_MS hoisted; waitForComponentJobDone; reloadCaps after jobs
# - effectiveInstalled drawer buttons (fixes v19 showInstallBtn without defs)
# - log join \\n fix; WARP settings UI block
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v20' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v20] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# --- constants at top (bridge pool + drawer TTL) ---
const_block = "const COMPONENT_JOB_UI_TTL_MS = 120_000;\nconst JOB_MSG_TTL_MS = 45_000;\n\n"
if "const JOB_MSG_TTL_MS = 45_000;" in t and const_block.strip() not in t[:1200]:
    t = t.replace("const COMPONENT_JOB_UI_TTL_MS = 120_000;\nconst JOB_MSG_TTL_MS = 45_000;\n\n", "", 1)
    marker = "/* olc-panel-ui-warp */\n"
    if marker in t:
        t = t.replace(marker, marker + const_block, 1)
    else:
        t = const_block + t

# --- log newline fix ---
t = t.replace('.join("\\\\n")', '.join("\\n")')
t = t.replace(
    '<pre className="max-h-48 overflow-auto text-xs">{activeJobLines.slice(-250).join("\\n")}</pre>',
    '<pre className="max-h-48 overflow-auto whitespace-pre-wrap text-xs leading-relaxed">{activeJobLines.slice(-250).join("\\n")}</pre>',
)

# --- waitForComponentJobDone ---
if "async function waitForComponentJobDone" not in t:
    wait_fn = '''
async function waitForComponentJobDone(component: string, jobId: string, timeoutMs = 600_000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const res = await fetch("/api/components/jobs", { cache: "no-store" });
      if (!res.ok) break;
      const body = (await res.json()) as { jobs?: { component?: string; job_id?: string; status?: string }[] };
      const job = (body.jobs ?? []).find((j) => j.component === component && j.job_id === jobId);
      if (!job || job.status === "done" || job.status === "failed") return job?.status ?? "done";
    } catch {
      /* ignore */
    }
    await new Promise((r) => window.setTimeout(r, 2000));
  }
  return "timeout";
}

'''
    t = t.replace("const COMPONENT_DRAWER_ITEMS = [", wait_fn + "const COMPONENT_DRAWER_ITEMS = [", 1)

# --- useCapabilities: export reloadCaps ---
if "reloadCaps: reloadCapsNow" not in t:
    old_ret = "  return { caps, visible };\n}"
    new_ret = '''  const reloadCapsNow = async () => {
    try {
      const res = await fetch("/api/capabilities", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as Capabilities;
      setCaps(body);
    } catch {
      /* ignore */
    }
  };
  return { caps, visible, reloadCaps: reloadCapsNow };
}'''
    if old_ret in t:
        t = t.replace(old_ret, new_ret, 1)

t = t.replace(
    "const { caps } = useCapabilities();",
    "const { caps, reloadCaps } = useCapabilities();",
    1,
)

# --- run(): poll job + reload caps ---
old_run_tail = """        const finalStatus = await waitForComponentJobDone(name, jobId);
        await loadJobs();
        window.dispatchEvent(new Event("olc-capabilities-changed"));
        window.dispatchEvent(new Event("olc-features-changed"));"""
new_run_tail = """        const finalStatus = await waitForComponentJobDone(name, jobId);
        await loadJobs();
        await reloadCaps();
        window.dispatchEvent(new Event("olc-capabilities-changed"));
        window.dispatchEvent(new Event("olc-features-changed"));"""
if old_run_tail in t and "await reloadCaps();" not in t:
    t = t.replace(old_run_tail, new_run_tail, 1)

# --- drawer button state (replace v19 broken or legacy patterns) ---
old_btn_a = """              const showInstallBtn = jobAction === "install" || (!jobAction && !installed);
              const showDeleteBtn = jobAction === "uninstall" || (!jobAction && installed);"""
old_btn_b = """              const jobAction = isRunning ? j?.action : undefined;
              const showInstallBtn = jobAction === "install" || (!jobAction && !installed);
              const showDeleteBtn = jobAction === "uninstall" || (!jobAction && installed);"""
new_btn = """              const jobAction = isRunning ? j?.action : undefined;
              const jobDone = j?.status === "done";
              const effectiveInstalled =
                isRunning && jobAction === "uninstall" ? false
                : isRunning && jobAction === "install" ? false
                : jobDone && j?.action === "uninstall" ? false
                : jobDone && j?.action === "install" ? true
                : installed;
              const showInstallBtn = isRunning ? jobAction === "install" : !effectiveInstalled;
              const showDeleteBtn = isRunning ? jobAction === "uninstall" : effectiveInstalled;"""
if old_btn_b in t:
    t = t.replace(old_btn_b, new_btn, 1)
elif old_btn_a in t:
    t = t.replace(
        "              const jobAction = isRunning ? j?.action : undefined;\n" + old_btn_a,
        new_btn,
        1,
    )
elif "effectiveInstalled" not in t and "showInstallBtn &&" in t:
    # v19 replaced buttons but left no variable defs — inject before showJob
    anchor = "              const showJob = j && componentJobUiVisible(j);"
    inject = new_btn + "\n              const showJob = j && componentJobUiVisible(j);"
    if anchor in t:
        t = t.replace(anchor, inject, 1)

# --- WARP settings UI (from v13, idempotent) ---
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

if "/* olc-panel-hotfix-v20 */" not in t:
    if "/* olc-panel-hotfix-v19 */" in t:
        t = t.replace("/* olc-panel-hotfix-v19 */", "/* olc-panel-hotfix-v19 */\n/* olc-panel-hotfix-v20 */", 1)
    else:
        t = "/* olc-panel-hotfix-v20 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v20] ok")
PY
