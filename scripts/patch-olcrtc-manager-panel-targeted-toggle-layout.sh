#!/usr/bin/env bash
# Targeted polish for the toggle rows explicitly reviewed in the panel UI.
set -euo pipefail

target="${1:-/tmp/olcrtc-manager-panel/src/main.tsx}"
[[ -f "$target" ]] || { echo "[targeted-toggle-layout] target not found: $target" >&2; exit 1; }

python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "OLC_TOGGLE_TARGETED_LAYOUT_V1"
if marker in text:
    print(f"[targeted-toggle-layout] already applied: {path}")
    raise SystemExit(0)

def replace_exact(old: str, new: str, label: str, count: int = 1) -> None:
    global text
    actual = text.count(old)
    if actual != count:
        raise SystemExit(f"[targeted-toggle-layout] {label}: expected {count}, got {actual}")
    text = text.replace(old, new, count)

# Extend the existing button only with an opt-in danger tone. Its default path
# remains byte-for-byte equivalent for every toggle not listed below.
start = text.find("/* OLC_TOGGLE_BUTTONS_UI_V4 */")
end = text.find("function InstanceDefaultsModal(", start)
if start < 0 or end < 0:
    raise SystemExit("[targeted-toggle-layout] toggle component anchors changed")
component = text[start:end]
component = component.replace(
    "/* OLC_TOGGLE_BUTTONS_UI_V4 */",
    "/* OLC_TOGGLE_BUTTONS_UI_V4 */\n/* OLC_TOGGLE_TARGETED_LAYOUT_V1 */",
    1,
)
component = component.replace(
    "  title?: string;\n  className?: string;",
    '  title?: string;\n  tone?: "default" | "danger";\n  className?: string;',
    1,
)
component = component.replace(
    "function OlcToggleButton({ checked = false, disabled = false, mixed = false, compact = false, title, className = \"\", onClick, onChange }: OlcToggleButtonProps) {",
    "function OlcToggleButton({ checked = false, disabled = false, mixed = false, compact = false, title, tone = \"default\", className = \"\", onClick, onChange }: OlcToggleButtonProps) {",
    1,
)
component = component.replace(
    '''  const stateClass = mixed
    ? "border-amber-500/40 bg-amber-500/10 text-amber-600 hover:bg-amber-500/20"
    : checked
      ? "border-green-500/40 bg-green-500/10 text-green-600 hover:bg-green-500/20"
      : "border-border bg-transparent text-foreground hover:bg-muted";''',
    '''  const stateClass = mixed
    ? "border-amber-500/40 bg-amber-500/10 text-amber-600 hover:bg-amber-500/20"
    : checked
      ? tone === "danger"
        ? "border-red-500/40 bg-red-500/10 text-red-400 hover:bg-red-500/20"
        : "border-green-500/40 bg-green-500/10 text-green-600 hover:bg-green-500/20"
      : "border-border bg-transparent text-foreground hover:bg-muted";''',
    1,
)
if marker not in component or 'tone === "danger"' not in component:
    raise SystemExit("[targeted-toggle-layout] toggle component shape changed")
text = text[:start] + component + text[end:]

# 1. Autologs: the button already displays the state; remove the duplicated
# trailing Вкл/Выкл text and leave the rest of the settings row untouched.
replace_exact(
    '                <span className={autologi ? "text-emerald-600 font-medium" : ""}>{autologi ? "Вкл" : "Выкл"}</span>\n',
    "",
    "autologs duplicated state",
)

# 2-3. Subscription ban blocks: label first, one danger-coloured state button
# on the right. This avoids a bright green control inside a red warning card.
replace_exact(
    '''            <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <OlcToggleButton  checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void saveSettings({ ban_no_hwid: e.target.checked }); }} />
              Блокировать запросы без hwid (Compatibility-режим olcbox) — действует в обоих режимах
            </div>''',
    '''            <div className="flex items-center justify-between gap-3 text-[11px] text-muted-foreground">
              <span>Блокировать запросы без hwid (Compatibility-режим olcbox) — действует в обоих режимах</span>
              <OlcToggleButton tone="danger" checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void saveSettings({ ban_no_hwid: e.target.checked }); }} />
            </div>''',
    "global ban without hwid",
)
replace_exact(
    '''            <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <OlcToggleButton  checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void save({ ban_no_hwid: e.target.checked }); }} />
              Блокировать запросы без hwid (Compatibility-режим olcbox) — действует в обоих режимах
            </div>''',
    '''            <div className="flex items-center justify-between gap-3 text-[11px] text-muted-foreground">
              <span>Блокировать запросы без hwid (Compatibility-режим olcbox) — действует в обоих режимах</span>
              <OlcToggleButton tone="danger" checked={banNoHwid} disabled={busy} onChange={(e) => { setBanNoHwid(e.target.checked); void save({ ban_no_hwid: e.target.checked }); }} />
            </div>''',
    "client ban without hwid",
)

# 4. OlcRTC Jitsi TLS setting: readable setting name first, button aligned right.
replace_exact(
    '''                <div className="flex items-center gap-2 text-xs">
                  <OlcToggleButton  checked={Boolean(settings.jitsi_insecure_tls)} onChange={(e) => setBool("jitsi_insecure_tls", e.target.checked)} />
                  {t("olcrtcJitsiTls")}
                </div>''',
    '''                <div className="flex items-center justify-between gap-3 text-xs">
                  <span>{t("olcrtcJitsiTls")}</span>
                  <OlcToggleButton checked={Boolean(settings.jitsi_insecure_tls)} onChange={(e) => setBool("jitsi_insecure_tls", e.target.checked)} />
                </div>''',
    "Jitsi TLS row",
)

# 5. Verbose log view: text on the left, state button on the right.
replace_exact(
    '''              <div className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                <OlcToggleButton  checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
                {t("logsVerbose")}
              </div>''',
    '''              <div className="flex min-w-[230px] items-center justify-between gap-3 text-xs text-muted-foreground">
                <span>{t("logsVerbose")}</span>
                <OlcToggleButton checked={logsVerbose} onChange={(event) => setLogsVerbose(event.target.checked)} />
              </div>''',
    "verbose logs row",
)

# 6. Notification preferences: compact right-aligned buttons keep the source
# list readable without a column of large green controls before every label.
replace_exact(
    '''            <div className="flex items-center gap-2 text-xs">
              <OlcToggleButton  checked={Boolean(s.show_toast)} onChange={(e) => setS({ ...s, show_toast: e.target.checked })} />
              Всплывающие подсказки (toast)
            </div>''',
    '''            <div className="flex items-center justify-between gap-3 text-xs">
              <span>Всплывающие подсказки (toast)</span>
              <OlcToggleButton compact checked={Boolean(s.show_toast)} onChange={(e) => setS({ ...s, show_toast: e.target.checked })} />
            </div>''',
    "toast preference row",
)
replace_exact(
    '''              <div key={k} className="flex items-center gap-2 text-xs">
                <OlcToggleButton  checked={sources[k] !== false} onChange={(e) => setSource(k, e.target.checked)} />
                {k}
              </div>''',
    '''              <div key={k} className="flex items-center justify-between gap-3 py-0.5 text-xs">
                <span>{k}</span>
                <OlcToggleButton compact checked={sources[k] !== false} onChange={(e) => setSource(k, e.target.checked)} />
              </div>''',
    "notification source rows",
)

# 7. Autodetector: its title and button form one header; remove the redundant
# static word Включён beneath the explanatory text.
replace_exact(
    '''      <div className="font-medium">Автодетектор ошибок</div>
      <p className="text-xs text-muted-foreground">Сканирует логи и состояние сервисов, создаёт уведомления в колокольчике.</p>
      <div className="flex items-center gap-2 text-xs">
        <OlcToggleButton  checked={Boolean(s.enabled)} onChange={(e) => setS({ ...s, enabled: e.target.checked })} />
        Включён
      </div>''',
    '''      <div className="flex items-center justify-between gap-3">
        <div className="font-medium">Автодетектор ошибок</div>
        <OlcToggleButton checked={Boolean(s.enabled)} onChange={(e) => setS({ ...s, enabled: e.target.checked })} />
      </div>
      <p className="text-xs text-muted-foreground">Сканирует логи и состояние сервисов, создаёт уведомления в колокольчике.</p>''',
    "autodetector header",
)

# 8. Global subscription randomization: keep the existing title above and only
# the button below it; remove the second copy of the title and hover scaling.
replace_exact(
    '''        <div className="flex items-center gap-2 text-xs cursor-pointer">
          <OlcToggleButton
''' + "            " + '''
            checked={enabled}
            onChange={() => void toggle()}
            className="cursor-pointer transition-transform hover:scale-110"
          />
          <span className={enabled ? "text-amber-600 font-medium transition-colors" : "transition-colors"}>
            Глобальная рандомизация
          </span>
        </div>''',
    '''        <div className="flex items-center text-xs">
          <OlcToggleButton checked={enabled} onChange={() => void toggle()} />
        </div>''',
    "global randomization row",
)

# 9. Zapret auto-sync, 10. RU CIDR, 11. bridge pool auto-update: descriptive
# label first, state button aligned to the right of only that reviewed row.
replace_exact(
    '''                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <OlcToggleButton
''' + "                    " + '''
                    checked={Boolean(settings.auto_sync)}
                    onChange={(e) => setBool("auto_sync", e.target.checked)}
                  />
                  {t("zapretAutoSync")}
                </div>''',
    '''                <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
                  <span>{t("zapretAutoSync")}</span>
                  <OlcToggleButton checked={Boolean(settings.auto_sync)} onChange={(e) => setBool("auto_sync", e.target.checked)} />
                </div>''',
    "Zapret auto-sync row",
)
replace_exact(
    '''                  <div className="flex items-center gap-2 text-sm">
                    <OlcToggleButton  checked={Boolean(settings.cidr_only)} onChange={(e) => setBool("cidr_only", e.target.checked)} />
                    {t("splitCidrOnly")}
                  </div>''',
    '''                  <div className="flex items-center justify-between gap-3 text-sm">
                    <span>{t("splitCidrOnly")}</span>
                    <OlcToggleButton checked={Boolean(settings.cidr_only)} onChange={(e) => setBool("cidr_only", e.target.checked)} />
                  </div>''',
    "RU CIDR row",
)
replace_exact(
    '''            <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <OlcToggleButton
''' + "                " + '''
                checked={Boolean(sys.auto_update)}
                onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })}
              />
              Автообновление пула (cron, ~каждые 6ч)
            </div>''',
    '''            <div className="flex items-center justify-between gap-3 text-[11px] text-muted-foreground">
              <span>Автообновление пула (cron, ~каждые 6ч)</span>
              <OlcToggleButton compact checked={Boolean(sys.auto_update)} onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })} />
            </div>''',
    "bridge pool auto-update row",
)

path.write_text(text)
print(f"[targeted-toggle-layout] applied: {path}")
PY
