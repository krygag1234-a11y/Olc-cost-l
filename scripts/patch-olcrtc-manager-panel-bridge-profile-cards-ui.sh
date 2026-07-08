#!/usr/bin/env bash
# Replace bridge profile dropdown with card-based UI (radio buttons + bridge count).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-bridge-profile-cards-ui' "$MAIN_TSX" && { echo "[patch-bridge-profile-cards-ui] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Marker
if 'olc-bridge-profile-cards-ui' not in t:
    t = t.replace('function BridgesSettingsFields', '/* olc-bridge-profile-cards-ui */\nfunction BridgesSettingsFields', 1)

# Helper function to count bridges in a profile
count_helper = '''
  const countBridges = (profile: Record<string, unknown>) => {
    const mode = String(profile.mode ?? "manual");
    if (mode === "manual") {
      const bridges = String(profile.bridges ?? "");
      return bridges.split("\\n").filter(l => l.trim().startsWith("Bridge")).length;
    }
    return 0;
  };
'''

# Insert helper after const declarations at the start of BridgesSettingsFields
if 'const countBridges' not in t:
    # Find the line after poolUiActive declaration
    anchor = 'const poolUiActive = poolUiOpen;'
    if anchor in t:
        t = t.replace(anchor, anchor + '\n' + count_helper, 1)

# Old dropdown + profile cards (lines 2671-2729 from read)
old_profiles = '''      <label className="grid gap-1 text-xs text-muted-foreground">
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
          <button type="button" className="rounded border border-border px-2 py-1 hover:bg-muted" disabled={poolBusy || jobStatus === "running"} onClick={() => void refreshPool(String(sys.types ?? "obfs4,webtunnel"))}>
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
      )}'''

# New card-based UI with radio buttons
new_profiles = '''      <div className="space-y-2">
        <div className="text-xs text-muted-foreground font-medium">Профили мостов</div>

        {/* Системный профиль - карточка с radio */}
        <label
          className={`flex items-start gap-3 rounded border p-3 cursor-pointer transition-colors ${
            activeId === "system" ? "border-primary bg-primary/10" : "border-border hover:bg-muted/30"
          }`}
        >
          <input
            type="radio"
            name="bridge-profile"
            value="system"
            checked={activeId === "system"}
            onChange={(e) => patchProfiles({ ...prof, active_profile: e.target.value })}
            className="mt-1"
          />
          <div className="flex-1 space-y-2">
            <div>
              <div className="font-medium text-sm">Оригинальный (системный)</div>
              <div className="text-xs text-muted-foreground mt-1">
                {ps.obfs4 ?? 0} obfs4 + {ps.webtunnel ?? 0} webtunnel = {ps.total ?? 0} мостов
              </div>
              <div className="text-xs text-muted-foreground/80 mt-1">
                Обновляется из встроенных источников Olc-cost-l
              </div>
            </div>

            {activeId === "system" && (
              <div className="pt-2 border-t border-border/50 space-y-2">
                <label className="grid gap-1">
                  <span className="text-xs">Типы мостов</span>
                  <select
                    className="h-8 rounded border border-border bg-background px-2 text-xs"
                    value={String(sys.types ?? "obfs4,webtunnel")}
                    onChange={(e) => patchProfiles({ ...prof, system: { ...sys, types: e.target.value } })}
                  >
                    <option value="obfs4">obfs4</option>
                    <option value="webtunnel">webTunnel</option>
                    <option value="obfs4,webtunnel">obfs4 + webTunnel</option>
                  </select>
                </label>
                <label className="flex items-center gap-2 text-xs">
                  <input
                    type="checkbox"
                    checked={Boolean(sys.auto_update)}
                    onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })}
                  />
                  Автообновление (cron)
                </label>
                {!Boolean(sys.auto_update) && (
                  <button
                    type="button"
                    className="rounded border border-border px-2 py-1 text-xs hover:bg-muted"
                    disabled={poolBusy || jobStatus === "running"}
                    onClick={() => void refreshPool(String(sys.types ?? "obfs4,webtunnel"))}
                  >
                    Обновить сейчас
                  </button>
                )}
              </div>
            )}
          </div>
        </label>

        {/* Пользовательские профили - карточки с radio */}
        {custom.map((pr) => (
          <label
            key={String(pr.id)}
            className={`flex items-start gap-3 rounded border p-3 cursor-pointer transition-colors ${
              activeId === String(pr.id) ? "border-primary bg-primary/10" : "border-border hover:bg-muted/30"
            }`}
          >
            <input
              type="radio"
              name="bridge-profile"
              value={String(pr.id)}
              checked={activeId === String(pr.id)}
              onChange={(e) => patchProfiles({ ...prof, active_profile: e.target.value })}
              className="mt-1"
            />
            <div className="flex-1">
              <div className="font-medium text-sm">{String(pr.label ?? pr.id)}</div>
              <div className="text-xs text-muted-foreground mt-1">
                {countBridges(pr)} мостов · {String(pr.mode ?? "?")}
              </div>
            </div>
            <button
              type="button"
              className="text-destructive hover:text-destructive/80 text-sm"
              onClick={(e) => {
                e.preventDefault();
                removeProfile(String(pr.id));
              }}
              title="Удалить профиль"
            >
              ✕
            </button>
          </label>
        ))}
      </div>'''

if old_profiles in t:
    t = t.replace(old_profiles, new_profiles, 1)
else:
    print("[patch-bridge-profile-cards-ui] WARN: anchor not found, trying flexible match", file=sys.stderr)

p.write_text(t)
print("[patch-bridge-profile-cards-ui] ok")
PY
