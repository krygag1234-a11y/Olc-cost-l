#!/usr/bin/env bash
# UI v6: bridges profiles, notification settings opener, expanded forms, olcrtc logs.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-v6' "$MAIN_TSX" && { echo "[patch-panel-ui-v6] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
t = t.replace('import React, {', '/* olc-panel-ui-v6 */\nimport React, {', 1)

# Fix notification section broken listener
t = t.replace(
    '''  useEffect(() => {
    const h = () => setShowNotifSettings(true);
    window.addEventListener("olc-open-notification-settings", h);
    return () => window.removeEventListener("olc-open-notification-settings", h);
  }, []);
''',
    '',
    1,
)

# App: open settings from bell
if 'olc-open-notification-settings' not in t.split('function App()')[1].split('const checkAuth')[0]:
    t = t.replace(
        '  const checkAuth = async () => {',
        '''  useEffect(() => {
    const openNotifSettings = () => {
      void (async () => {
        setShowSettings(true);
        setNotice("");
        try {
          await loadSettings();
        } catch (err) {
          setNotice(err instanceof Error ? err.message : String(err));
        }
      })();
    };
    window.addEventListener("olc-open-notification-settings", openNotifSettings);
    return () => window.removeEventListener("olc-open-notification-settings", openNotifSettings);
  }, []);

  const checkAuth = async () => {''',
        1,
    )

# OlcRTC logs button
t = t.replace(
    'onClick={() => setLogFeature("zapret")}',
    'onClick={() => setLogFeature("olcrtc")}',
    1,
)

bridges_component = r'''
function BridgesSettingsFields({
  settings,
  setSettings,
  setMsg,
}: {
  settings: Record<string, unknown>;
  setSettings: React.Dispatch<React.SetStateAction<Record<string, unknown>>>;
  setMsg: (s: string) => void;
}) {
  const ps = (settings.pool_stats as Record<string, number>) ?? {};
  const prof = (settings.profiles as Record<string, unknown>) ?? {};
  const sys = (prof.system as Record<string, unknown>) ?? {};
  const custom = (prof.profiles as Record<string, unknown>[]) ?? [];
  const activeId = String(prof.active_profile ?? "system");
  const [addMode, setAddMode] = useState<"" | "manual" | "url">("");
  const [newLabel, setNewLabel] = useState("");
  const [newBridges, setNewBridges] = useState("");
  const [newUrls, setNewUrls] = useState("");

  const patchProfiles = (next: Record<string, unknown>) => {
    setSettings((s) => ({ ...s, profiles: next }));
  };

  const refreshPool = async (types: string) => {
    const res = await fetch("/api/settings/bridges", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "refresh_pool", types }),
    });
    setMsg(res.ok ? "Обновление пула запущено" : `HTTP ${res.status}`);
  };

  const addCustomProfile = () => {
    if (!newLabel.trim()) return;
    const id = `p-${Date.now().toString(36)}`;
    const entry: Record<string, unknown> = {
      id,
      label: newLabel.trim(),
      mode: addMode,
      readonly: false,
      auto_update: addMode === "url",
    };
    if (addMode === "manual") {
      entry.bridges = newBridges;
    } else {
      entry.urls = newUrls.split("\n").map((u) => u.trim()).filter(Boolean);
    }
    patchProfiles({ ...prof, profiles: [...custom, entry] });
    setAddMode("");
    setNewLabel("");
    setNewBridges("");
    setNewUrls("");
    setMsg("Профиль добавлен — нажмите «Сохранить»");
  };

  const removeProfile = (id: string) => {
    patchProfiles({ ...prof, profiles: custom.filter((x) => x.id !== id) });
    if (activeId === id) {
      patchProfiles({ ...prof, active_profile: "system", profiles: custom.filter((x) => x.id !== id) });
    }
  };

  return (
    <>
      <p className="text-xs text-muted-foreground">
        Пул: obfs4 {ps.obfs4 ?? 0}, webtunnel {ps.webtunnel ?? 0}, прочие {ps.other ?? 0}, всего {ps.total ?? 0}
      </p>
      <label className="grid gap-1 text-xs text-muted-foreground">
        Активный профиль
        <select
          className="h-8 rounded border border-border bg-background px-2"
          value={activeId}
          onChange={(e) => patchProfiles({ ...prof, active_profile: e.target.value })}
        >
          <option value="system">Оригинальный (системный)</option>
          {custom.map((pr) => (
            <option key={String(pr.id)} value={String(pr.id)}>
              {String(pr.label ?? pr.id)}
            </option>
          ))}
        </select>
      </label>
      <div className="rounded border border-border p-3 text-xs space-y-2">
        <div className="font-medium">Оригинальный профиль</div>
        <p className="text-muted-foreground">Нельзя удалить. Обновляется из встроенных источников Olc-cost-l.</p>
        <label className="grid gap-1">
          Типы мостов
          <select
            className="h-8 rounded border border-border bg-background px-2"
            value={String(sys.types ?? "obfs4,webtunnel")}
            onChange={(e) => patchProfiles({ ...prof, system: { ...sys, types: e.target.value } })}
          >
            <option value="obfs4">obfs4</option>
            <option value="webtunnel">webTunnel</option>
            <option value="obfs4,webtunnel">obfs4 + webTunnel</option>
          </select>
        </label>
        <label className="flex items-center gap-2">
          <input
            type="checkbox"
            checked={Boolean(sys.auto_update)}
            onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })}
          />
          Автообновление (cron)
        </label>
        {!Boolean(sys.auto_update) && (
          <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" onClick={() => void refreshPool(String(sys.types ?? "obfs4,webtunnel"))}>
            Обновить сейчас
          </button>
        )}
      </div>
      {custom.length > 0 && (
        <div className="space-y-2 text-xs">
          <div className="font-medium">Свои профили</div>
          {custom.map((pr) => (
            <div key={String(pr.id)} className="flex items-center justify-between rounded border border-border px-2 py-1">
              <span>
                {String(pr.label ?? pr.id)} ({String(pr.mode ?? "?")})
              </span>
              <button type="button" className="text-destructive hover:underline" onClick={() => removeProfile(String(pr.id))}>
                Удалить
              </button>
            </div>
          ))}
        </div>
      )}
      <div className="flex flex-wrap gap-2">
        <button type="button" className="rounded border border-border px-2 py-1 text-xs" onClick={() => setAddMode("manual")}>
          + Свои мосты
        </button>
        <button type="button" className="rounded border border-border px-2 py-1 text-xs" onClick={() => setAddMode("url")}>
          + Ссылка (raw)
        </button>
      </div>
      {addMode === "manual" && (
        <div className="rounded border border-dashed border-border p-2 space-y-2 text-xs">
          <input className="h-8 w-full rounded border border-border bg-background px-2" placeholder="Название профиля" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} />
          <textarea className="min-h-[80px] w-full rounded border border-border bg-background p-2 font-mono" placeholder="Bridge obfs4 ...&#10;Bridge webtunnel ..." value={newBridges} onChange={(e) => setNewBridges(e.target.value)} />
          <button type="button" className="rounded border border-primary px-2 py-1 text-primary" onClick={addCustomProfile}>
            Добавить профиль
          </button>
        </div>
      )}
      {addMode === "url" && (
        <div className="rounded border border-dashed border-border p-2 space-y-2 text-xs">
          <input className="h-8 w-full rounded border border-border bg-background px-2" placeholder="Название профиля" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} />
          <textarea className="min-h-[60px] w-full rounded border border-border bg-background p-2 font-mono" placeholder="https://.../bridges.txt (по строке)" value={newUrls} onChange={(e) => setNewUrls(e.target.value)} />
          <p className="text-muted-foreground">Формат raw: одна ссылка на строку, как на GitHub.</p>
          <button type="button" className="rounded border border-primary px-2 py-1 text-primary" onClick={addCustomProfile}>
            Добавить профиль
          </button>
        </div>
      )}
      <label className="grid gap-1 text-muted-foreground">
        Добавить одну строку в /etc/tor/bridges.conf
        <input
          className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
          placeholder="Bridge webtunnel ..."
          value={String(settings.custom_bridge ?? "")}
          onChange={(e) => setSettings((s) => ({ ...s, custom_bridge: e.target.value }))}
        />
      </label>
      <pre className="max-h-[160px] overflow-auto rounded border border-border bg-background p-2 text-xs">
        {String(settings.bridges_conf ?? "").slice(-3000) || "(пусто)"}
      </pre>
    </>
  );
}

'''

if 'function BridgesSettingsFields' not in t:
    t = t.replace('function ComponentSettingsModal(', bridges_component + 'function ComponentSettingsModal(', 1)

# Replace webtunnel bridges block
old_bridges = '''            {(feature === "webtunnel" || feature === "bridges") && (
              <>
                <p className="text-xs text-muted-foreground">
                  Пул: obfs4 {String((settings.pool_stats as Record<string, number>)?.obfs4 ?? 0)}, webtunnel {String((settings.pool_stats as Record<string, number>)?.webtunnel ?? 0)}
                </p>
                <label className="grid gap-1 text-muted-foreground">
                  Добавить мост (строка Bridge …)
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    placeholder="webtunnel 192.0.2.1:443 FINGERPRINT cert=..."
                    onChange={(e) => setStr("custom_bridge", e.target.value)}
                  />
                </label>
                <pre className="max-h-[200px] overflow-auto rounded border border-border bg-background p-2 text-xs">
                  {String(settings.bridges_conf ?? "").slice(-4000) || "(пусто)"}
                </pre>
              </>
            )}'''

new_bridges = '''            {feature === "webtunnel" && (
              <BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} />
            )}'''

if old_bridges in t:
    t = t.replace(old_bridges, new_bridges, 1)
elif 'BridgesSettingsFields' not in t.split('ComponentSettingsModal')[1][:12000]:
    t = t.replace(
        '            {feature === "olcrtc" && (',
        new_bridges + '\n            {feature === "olcrtc" && (',
        1,
    )

# save() — bridges payload
if 'bridge_profiles' not in t.split('const save = async')[1].split('};')[0]:
    t = t.replace(
        '''  const save = async () => {
    setSaving(true);
    setMsg("");
    try {
      const res = await fetch(`/api/settings/${apiName}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(settings),
      });''',
        '''  const save = async () => {
    setSaving(true);
    setMsg("");
    try {
      let payload: Record<string, unknown> = { ...settings };
      if (feature === "webtunnel") {
        const prof = settings.profiles as Record<string, unknown> | undefined;
        if (prof) {
          payload = {
            bridge_profiles: prof,
            active_profile: prof.active_profile,
            custom_bridge: settings.custom_bridge,
          };
        }
      }
      const res = await fetch(`/api/settings/${apiName}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });''',
        1,
    )

# Expanded zapret
if 'community_sync' not in t.split('feature === "zapret"')[1][:1200]:
    t = t.replace(
        '''                <p className="text-xs text-muted-foreground">
                  После сохранения: olc-feature zapret reload или olc-update
                </p>
              </>
            )}
            {feature === "tor" && (''',
        '''                <p className="text-xs text-muted-foreground">
                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}
                </p>
                <p className="text-xs text-muted-foreground">
                  После сохранения: olc-feature zapret reload или olc-update
                </p>
              </>
            )}
            {feature === "tor" && (''',
        1,
    )

# Expanded tor
if 'strict_nodes' not in t.split('feature === "tor"')[1][:1500]:
    t = t.replace(
        '''                <label className="grid gap-1 text-muted-foreground">
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
                </p>''',
        '''                <label className="grid gap-1 text-muted-foreground">
                  ExcludeExitNodes
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.exclude_exit_nodes ?? "")}
                    onChange={(e) => setStr("exclude_exit_nodes", e.target.value)}
                    placeholder="{ru},{by},{ua}"
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  StrictNodes (1 = только ExitNodes)
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.strict_nodes ?? "")}
                    onChange={(e) => setStr("strict_nodes", e.target.value)}
                    placeholder="0 или 1"
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  SOCKS listen: {String(settings.socks_listen ?? "9050")} · мосты в torrc: {settings.bridges_enabled ? "да" : "нет"}
                </p>
                <p className="text-xs text-muted-foreground">
                  После сохранения применяется configure-tor-exit (может потребоваться перезапуск инстансов).
                </p>''',
        1,
    )

# Expanded split
if 'force_tor_domains' not in t.split('feature === "split"')[1][:2000]:
    t = t.replace(
        '''                <p className="text-xs text-muted-foreground">
                  RU-direct списков: {String(settings.ru_direct_count ?? "?")}
                </p>
                <button''',
        '''                <label className="grid gap-1 text-muted-foreground">
                  Force-Tor домены
                  <textarea
                    className="min-h-[60px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.force_tor_domains ?? "")}
                    onChange={(e) => setStr("force_tor_domains", e.target.value)}
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  RU-blocked → Tor
                  <textarea
                    className="min-h-[60px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.blocked_tor_domains ?? "")}
                    onChange={(e) => setStr("blocked_tor_domains", e.target.value)}
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Panel carrier hosts
                  <textarea
                    className="min-h-[50px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.panel_hosts ?? "")}
                    onChange={(e) => setStr("panel_hosts", e.target.value)}
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  RU-direct: {String(settings.ru_direct_count ?? "?")} · CIDR: {String(settings.direct_cidrs_file ?? "—")} · только CIDR: {settings.cidr_only ? "да" : "нет"}
                </p>
                <button''',
        1,
    )

# Olcrtc settings show pinned sha
if 'olcrtc_pinned_sha' not in t.split('feature === "olcrtc"')[1][:800]:
    t = t.replace(
        '<p className="text-xs text-muted-foreground">Ветка olcrtc: fix/all (не master). После сохранения — olc-update или перезапуск инстансов.</p>',
        '<p className="text-xs text-muted-foreground">Ветка: fix/all · pin: <code>{String(settings.olcrtc_pinned_sha ?? "").slice(0, 12) || "—"}</code></p><p className="text-xs text-muted-foreground">После сохранения — olc-update или перезапуск инстансов.</p>',
        1,
    )

p.write_text(t)
print("[patch-panel-ui-v6] ok"); print(0); raise SystemExit(0)
PY
