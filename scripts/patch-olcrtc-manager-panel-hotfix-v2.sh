#!/usr/bin/env bash
# Hotfix v2: robust settings JSON parsing + autodetect mini panel + strategy UI.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v2' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Robust API parsing in settings modal load.
old_load = """        const res = await fetch(`/api/settings/${apiName}`, { cache: "no-store" });
        const body = (await res.json()) as { settings?: Record<string, unknown> };
        if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
        if (!cancelled) setSettings(body.settings ?? {});
"""
new_load = """        const res = await fetch(`/api/settings/${apiName}`, { cache: "no-store" });
        const raw = await res.text();
        let body: { settings?: Record<string, unknown>; error?: string } = {};
        try {
          body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown>; error?: string };
        } catch {
          body = { error: raw || undefined };
        }
        if (!res.ok) throw new Error(body.error || raw || `HTTP ${res.status}`);
        if (!cancelled) setSettings(body.settings ?? {});
"""
if old_load in t:
    t = t.replace(old_load, new_load, 1)

# Robust error parse in save.
old_save = """      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error((err as { error?: string }).error || `HTTP ${res.status}`);
      }
"""
new_save = """      if (!res.ok) {
        const raw = await res.text();
        let errText = raw;
        try {
          const err = (raw ? JSON.parse(raw) : {}) as { error?: string };
          errText = err.error || raw;
        } catch {
          /* keep raw text */
        }
        throw new Error(errText || `HTTP ${res.status}`);
      }
"""
if old_save in t:
    t = t.replace(old_save, new_save, 1)

# Robust parse in bridges onReload.
old_reload = 'onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const body = (await res.json()) as { settings?: Record<string, unknown> }; setSettings(body.settings ?? {}); }}'
new_reload = 'onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const raw = await res.text(); let body: { settings?: Record<string, unknown> } = {}; try { body = (raw ? JSON.parse(raw) : {}) as { settings?: Record<string, unknown> }; } catch { body = {}; } setSettings(body.settings ?? {}); }}'
if old_reload in t:
    t = t.replace(old_reload, new_reload, 1)

# Zapret strategy controls.
if "strategy_presets" not in t[t.find("{feature === \"zapret\""):t.find("{feature === \"tor\"")]:
    zap_insert_anchor = '                <p className="text-xs text-muted-foreground">\n                  После сохранения: olc-feature zapret reload или olc-update\n                </p>\n'
    zap_insert = """                <label className="grid gap-1 text-muted-foreground">
                  Стратегия zapret
                  <select
                    className="h-9 rounded-md border border-border bg-background px-2 text-xs"
                    value={String((settings.strategy_id ?? settings.strategy_current ?? settings.strategy ?? "") as string)}
                    onChange={(e) => setSettings((s) => ({ ...s, strategy_id: e.target.value }))}
                  >
                    {((settings.strategy_presets as { id?: string; label?: string }[] | undefined) ?? []).map((p) => (
                      <option key={String(p.id ?? "")} value={String(p.id ?? "")}>
                        {String(p.label ?? p.id ?? "")}
                      </option>
                    ))}
                  </select>
                </label>
                <p className="text-xs text-muted-foreground">
                  Текущая: {String(settings.strategy_current ?? settings.strategy ?? "—")}
                </p>
                <p className="text-xs text-muted-foreground">
                  После сохранения: olc-feature zapret reload или olc-update
                </p>
"""
    if zap_insert_anchor in t:
        t = t.replace(zap_insert_anchor, zap_insert, 1)

# Remove duplicated strategy info lines.
t = t.replace(
    '                <p className="text-xs text-muted-foreground">\n                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}\n                </p>\n                <p className="text-xs text-muted-foreground">\n                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}\n                </p>\n',
    '                <p className="text-xs text-muted-foreground">\n                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}\n                </p>\n',
    1,
)

# Errors modal should open autodetect mini panel.
t = t.replace(
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-settings")); setOpen(false); }}',
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-mini")); setOpen(false); }}',
    1,
)

# NotificationBell listens for mini-panel open event.
if 'olc-open-autodetect-mini' not in t[t.find("function NotificationBell()"):t.find("function ProjectUpdateButton")]:
    anchor = "  useEffect(() => {\n    void load();\n"
    block = """  useEffect(() => {
    const openMini = () => {
      setOpen(false);
      setPrefsOpen(true);
    };
    window.addEventListener("olc-open-autodetect-mini", openMini);
    return () => window.removeEventListener("olc-open-autodetect-mini", openMini);
  }, []);

"""
    if anchor in t:
        t = t.replace(anchor, block + anchor, 1)

if "olc-panel-hotfix-v2" not in t:
    t = t.replace("/* olc-panel-hotfix-v1 */", "/* olc-panel-hotfix-v1 */\n/* olc-panel-hotfix-v2 */", 1)

p.write_text(t)
print("[patch-panel-hotfix-v2] ok"); print(0); raise SystemExit(0)
PY
