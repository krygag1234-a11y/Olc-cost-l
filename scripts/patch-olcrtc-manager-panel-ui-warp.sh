#!/usr/bin/env bash
# WARP in header, Сеть и обход, Компоненты VPS; mutual exclusion with Tor.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-warp' "$MAIN_TSX" && { echo "[patch-panel-ui-warp] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
marker = "/* olc-panel-ui-warp */"
if "olc-panel-ui-v10" in t:
    t = t.replace("/* olc-panel-ui-v10 */", marker, 1)
elif marker not in t:
    t = t.replace("import React, {", marker + "\nimport React, {", 1)

t = t.replace(
    'type FeatureName = "zapret" | "tor" | "split" | "webtunnel" | "olcrtc";',
    'type FeatureName = "zapret" | "tor" | "split" | "webtunnel" | "warp" | "olcrtc";',
    1,
)

# dedupe accidental duplicate olcrtc hints from legacy patches
t = re.sub(
    r'(  olcrtc: \{[^}]+\},)\s*(?:  olcrtc: \{[^}]+\},\s*)+',
    r'\1\n',
    t,
    count=1,
)

if '  warp: {' not in t:
    t = t.replace(
        '''  webtunnel: {
    title: "Мосты",
    lines: [
      "Бинарь: /usr/bin/webtunnel-client (mirror-cry)",
      "При выкл — Tor использует obfs4/snowflake.",
      "Включение может занять 1–2 мин (скачивание).",
    ],
  },
};''',
        '''  webtunnel: {
    title: "Мосты",
    lines: [
      "Бинарь: /usr/bin/webtunnel-client (mirror-cry)",
      "При выкл — Tor использует obfs4/snowflake.",
      "Включение может занять 1–2 мин (скачивание).",
    ],
  },
  warp: {
    title: "WARP",
    lines: [
      "Cloudflare WARP proxy (SOCKS5, обычно 127.0.0.1:40000).",
      "Недоступен при включённом Tor — выберите один egress.",
      "Профиль foreign-warp: install.sh --with-warp",
    ],
  },
};''',
        1,
    )

if 'name === "warp"' not in t.split('async function postFeatureToggle')[1].split('notifyFeaturesChanged')[0]:
    t = t.replace(
        '''  if (name === "split" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — split маршрутизирует остальной трафик через exit");
  }''',
        '''  if (name === "split" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — split маршрутизирует остальной трафик через exit");
  }
  if (name === "warp" && enabled && flags && flags.tor) {
    throw new Error("WARP недоступен при включённом Tor — сначала выключите Tor");
  }
  if (name === "tor" && enabled && flags && flags.warp) {
    throw new Error("Tor недоступен при включённом WARP — сначала выключите WARP");
  }''',
        1,
    )

if '{ name: "warp"' not in t.split('function HeaderNetworkToggles')[1].split('return (')[0]:
    t = t.replace(
        '''  const items: { name: FeatureName; label: string }[] = [
    { name: "zapret", label: "Zp" },
    { name: "tor", label: "Tor" },
    { name: "split", label: "Sp" },
    { name: "webtunnel", label: "Мосты" },
  ];''',
        '''  const items: { name: FeatureName; label: string }[] = [
    { name: "zapret", label: "Zp" },
    { name: "tor", label: "Tor" },
    { name: "split", label: "Sp" },
    { name: "webtunnel", label: "Мосты" },
    { name: "warp", label: "WARP" },
  ];''',
        1,
    )
    t = t.replace(
        '''          const splitBlocked = it.name === "split" && !flags?.tor;
          return (''',
        '''          const splitBlocked = it.name === "split" && !flags?.tor;
          const warpBlocked = it.name === "warp" && Boolean(flags?.tor);
          const torBlocked = it.name === "tor" && Boolean(flags?.warp);
          const blocked = splitBlocked || warpBlocked || torBlocked;
          const blockTitle = warpBlocked
            ? "WARP недоступен при включённом Tor"
            : torBlocked
              ? "Tor недоступен при включённом WARP"
              : splitBlocked
                ? "Сначала Tor"
                : `${it.name}: ${on ? "on" : "off"}`;
          return (''',
        1,
    )
    t = t.replace(
        '''                title={splitBlocked ? "Сначала Tor" : `${it.name}: ${on ? "on" : "off"}`}
                className={`inline-flex h-7 min-w-[2rem] items-center justify-center rounded-l px-1.5 text-[11px] font-medium disabled:opacity-50 ${
                  on ? "bg-emerald-500/25 text-emerald-300" : "text-muted-foreground hover:bg-muted"
                }`}
                disabled={busy !== null || splitBlocked}''',
        '''                title={blockTitle}
                className={`inline-flex h-7 min-w-[2rem] items-center justify-center rounded-l px-1.5 text-[11px] font-medium disabled:opacity-50 ${
                  on ? "bg-emerald-500/25 text-emerald-300" : "text-muted-foreground hover:bg-muted"
                }`}
                disabled={busy !== null || blocked}''',
        1,
    )

if '{ name: "warp", label: "WARP"' not in t.split('function FeaturesPanel')[1].split('return (')[0]:
    t = t.replace(
        '''  const rows: { name: FeatureName; label: string; hint: string }[] = [
    { name: "zapret", label: "Zapret", hint: "DPI bypass for blocked .ru on direct egress" },
    { name: "tor",     label: "Tor",     hint: "SOCKS5 9050 + bridges (RU VPS)" },
    { name: "split",   label: "Split routing", hint: "*.ru / CDN → direct; rest → Tor" },
    { name: "webtunnel", label: "Мосты", hint: "obfs4 + webtunnel, пул и профили" },
  ];''',
        '''  const rows: { name: FeatureName; label: string; hint: string }[] = [
    { name: "zapret", label: "Zapret", hint: "DPI bypass for blocked .ru on direct egress" },
    { name: "tor",     label: "Tor",     hint: "SOCKS5 9050 + bridges (RU VPS)" },
    { name: "split",   label: "Split routing", hint: "*.ru / CDN → direct; rest → Tor" },
    { name: "webtunnel", label: "Мосты", hint: "obfs4 + webtunnel, пул и профили" },
    { name: "warp", label: "WARP", hint: "Cloudflare proxy egress; недоступен при Tor" },
  ];''',
        1,
    )
    t = t.replace(
        '''            Вкл/выкл zapret · tor · split · webtunnel без переустановки.''',
        '''            Вкл/выкл zapret · tor · split · webtunnel · warp без переустановки.''',
        1,
    )
    t = t.replace(
        '''                    disabled={busy !== null || (row.name === "split" && !enabled && !data.flags?.tor)}''',
        '''                    disabled={
                      busy !== null ||
                      (row.name === "split" && !enabled && !data.flags?.tor) ||
                      (row.name === "warp" && !enabled && Boolean(data.flags?.tor)) ||
                      (row.name === "tor" && !enabled && Boolean(data.flags?.warp))
                    }''',
        1,
    )

if 'const apiName = feature === "webtunnel"' in t and 'feature === "warp"' not in t:
    t = t.replace(
        'const apiName = feature === "webtunnel" ? "bridges" : feature === "olcrtc" ? "olcrtc" : feature;',
        'const apiName = feature === "webtunnel" ? "bridges" : feature === "olcrtc" ? "olcrtc" : feature === "warp" ? "warp" : feature;',
        1,
    )

if '{feature === "warp"' not in t:
    t = t.replace(
        '''            {feature === "webtunnel" && (
              <BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const body = (await res.json()) as { settings?: Record<string, unknown> }; setSettings(body.settings ?? {}); }} />
            )}''',
        '''            {feature === "warp" && (
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
            )}
            {feature === "webtunnel" && (
              <BridgesSettingsFields settings={settings} setSettings={setSettings} setMsg={setMsg} onReload={async () => { const res = await fetch(`/api/settings/bridges`, { cache: "no-store" }); const body = (await res.json()) as { settings?: Record<string, unknown> }; setSettings(body.settings ?? {}); }} />
            )}''',
        1,
    )

# Remove WARP from olcrtc block (now separate component)
t = re.sub(
    r'\s*<label className="grid gap-1 text-muted-foreground">\s*WARP proxy \(optional\)[\s\S]*?</label>',
    '',
    t,
    count=1,
)

if '{ id: "warp"' not in t:
    t = t.replace(
        '''const COMPONENT_DRAWER_ITEMS = [
  { id: "zapret", label: "Zapret (DPI)" },
  { id: "tor", label: "Tor" },
  { id: "split", label: "Split" },
  { id: "bridges", label: "Мосты" },
] as const;''',
        '''const COMPONENT_DRAWER_ITEMS = [
  { id: "zapret", label: "Zapret (DPI)" },
  { id: "tor", label: "Tor" },
  { id: "split", label: "Split" },
  { id: "bridges", label: "Мосты" },
  { id: "warp", label: "WARP (Cloudflare)" },
] as const;''',
        1,
    )

if 'name === "webtunnel" ? "bridges"' in t.split('function useCapabilities')[1]:
    t = t.replace(
        'const key = name === "webtunnel" ? "bridges" : name;',
        'const key = name === "webtunnel" ? "bridges" : name === "warp" ? "warp" : name;',
        1,
    )

p.write_text(t)
print("[patch-panel-ui-warp] ok"); raise SystemExit(0)
PY
