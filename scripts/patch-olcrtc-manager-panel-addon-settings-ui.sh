#!/usr/bin/env bash
# B4: clarify + restructure the addon settings modal (ComponentSettingsModal).
#  1. Show a per-addon intro banner (uses the existing FEATURE_SETTINGS_HINTS
#     table, which was defined but never rendered) explaining what the addon does.
#  2. Add reusable SettingsSection (titled block) + SettingField (label + caption)
#     helpers for consistent grouping, spacing and readable captions.
#  3. Rewrite the raw Tor + Zapret field lists into titled sections with captions,
#     example placeholders and risk warnings.
# Idempotent. Target: manager src/main.tsx. Run late (after modal-memory).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-addon-settings-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-addon-settings-ui] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-addon-settings-ui] {label}: ok")
    else:
        print(f"[patch-addon-settings-ui] WARN {label}: anchor not found")

# --- 1. Reusable presentational helpers before ComponentSettingsModal ---
repl(
    'function ComponentSettingsModal({',
    '''function SettingsSection({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-border bg-muted/10 p-3">
      <div className="mb-2">
        <h3 className="text-sm font-semibold text-foreground">{title}</h3>
        {hint && <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">{hint}</p>}
      </div>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

function SettingField({
  label,
  caption,
  value,
  onChange,
  placeholder,
  mono = true,
}: {
  label: string;
  caption?: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  mono?: boolean;
}) {
  return (
    <label className="grid gap-1">
      <span className="text-xs font-medium text-foreground">{label}</span>
      {caption && <span className="text-[11px] leading-snug text-muted-foreground">{caption}</span>}
      <input
        className={`h-9 rounded-md border border-border bg-background px-2 text-xs ${mono ? "font-mono" : ""}`}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
      />
    </label>
  );
}

function AddonSettingsIntro({ feature }: { feature: FeatureName }) {
  const hint = FEATURE_SETTINGS_HINTS[feature];
  if (!hint || !hint.lines?.length) return null;
  return (
    <div className="rounded-lg border border-primary/30 bg-primary/5 p-3">
      <p className="text-xs font-semibold text-foreground">{hint.title}</p>
      <ul className="mt-1 list-disc space-y-0.5 pl-4 text-[11px] leading-snug text-muted-foreground">
        {hint.lines.map((line, i) => (
          <li key={i}>{line}</li>
        ))}
      </ul>
    </div>
  );
}

function ComponentSettingsModal({''',
    "settings helpers + intro",
    guard='function AddonSettingsIntro(',
)

# --- 2. Render the intro banner at the top of the loaded body ---
repl(
    '''        ) : (
          <>
            {feature === "zapret" && (''',
    '''        ) : (
          <>
            <AddonSettingsIntro feature={feature} />
            {feature === "zapret" && (''',
    "render intro banner",
    guard='<AddonSettingsIntro feature={feature} />',
)

# --- 3. Rewrite the Tor block into titled sections with captions/examples ---
tor_old = '''            {feature === "tor" && (
              <>
                <p className="text-xs text-muted-foreground">{t("torSocksPort", { port: String(settings.socks_port ?? "9050") })}</p>
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
                <label className="grid gap-1 text-muted-foreground">
                  StrictNodes (1 = только ExitNodes)
                  <input
                    className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs"
                    value={String(settings.strict_nodes ?? "")}
                    onChange={(e) => setStr("strict_nodes", e.target.value)}
                    placeholder="0 или 1"
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  SocksPort
                  <input className="h-9 rounded-md border border-border bg-background px-2 font-mono text-xs" value={String(settings.socks_listen ?? "")} onChange={(e) => setStr("socks_listen", e.target.value)} placeholder="9050" />
                </label>
                <p className="text-xs text-muted-foreground">
                  {t("torTestLine", { test: String(settings.test_socks ?? "—"), safe: String(settings.safe_socks ?? "—"), dns: String(settings.dns_port ?? "—") })}
                </p>
                <p className="text-xs text-muted-foreground">
                  {t("torBridgesLine", { wt: settings.webtunnel_client ? t("yes") : t("no"), bridges: settings.bridges_enabled ? t("yes") : t("no") })}
                </p>
                <p className="text-xs text-muted-foreground">
                  {t("torAfterSave")}
                </p>
              </>'''
tor_new = '''            {feature === "tor" && (
              <>
                <SettingsSection
                  title="Страны выхода (Exit nodes)"
                  hint="Через какие страны выпускать зарубежный трафик. Коды в фигурных скобках, через запятую. Оставьте пустым — Tor выберет автоматически."
                >
                  <SettingField
                    label="ExitNodes — разрешённые страны выхода"
                    caption="Пример: {de},{nl},{fi} — Германия, Нидерланды, Финляндия. Пусто = любая страна."
                    value={String(settings.exit_nodes ?? "")}
                    onChange={(v) => setStr("exit_nodes", v)}
                    placeholder="{de},{nl},{fi}"
                  />
                  <SettingField
                    label="ExcludeExitNodes — запрещённые страны"
                    caption="Пример: {ru},{by},{ua} — никогда не выходить через эти страны."
                    value={String(settings.exclude_exit_nodes ?? "")}
                    onChange={(v) => setStr("exclude_exit_nodes", v)}
                    placeholder="{ru},{by},{ua}"
                  />
                  <SettingField
                    label="StrictNodes — строгий режим"
                    caption="1 = использовать ТОЛЬКО указанные ExitNodes (если недоступны — соединения не будет). 0 = мягко, как предпочтение."
                    value={String(settings.strict_nodes ?? "")}
                    onChange={(v) => setStr("strict_nodes", v)}
                    placeholder="0 или 1"
                  />
                </SettingsSection>
                <SettingsSection
                  title="Локальный порт SOCKS"
                  hint={t("torSocksPort", { port: String(settings.socks_port ?? "9050") })}
                >
                  <SettingField
                    label="SocksPort — порт прослушивания"
                    caption="Порт локального SOCKS5-прокси на 127.0.0.1. По умолчанию 9050 — меняйте только при конфликте портов."
                    value={String(settings.socks_listen ?? "")}
                    onChange={(v) => setStr("socks_listen", v)}
                    placeholder="9050"
                  />
                </SettingsSection>
                <div className="space-y-1 rounded-md border border-border bg-muted/10 p-3 text-[11px] text-muted-foreground">
                  <p>{t("torTestLine", { test: String(settings.test_socks ?? "—"), safe: String(settings.safe_socks ?? "—"), dns: String(settings.dns_port ?? "—") })}</p>
                  <p>{t("torBridgesLine", { wt: settings.webtunnel_client ? t("yes") : t("no"), bridges: settings.bridges_enabled ? t("yes") : t("no") })}</p>
                  <p className="text-amber-400">{t("torAfterSave")}</p>
                </div>
              </>'''
repl(tor_old, tor_new, "restructure tor block", guard='Страны выхода (Exit nodes)')

# --- 4. Zapret: add captions to the free-text fields (keep behavior) ---
repl(
    '''                <label className="grid gap-1 text-muted-foreground">
                  {t("zapretExcludeDomains")}
                  <textarea
                    className="min-h-[100px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.exclude_domains ?? "")}
                    onChange={(e) => setStr("exclude_domains", e.target.value)}
                  />
                </label>''',
    '''                <label className="grid gap-1">
                  <span className="text-xs font-medium text-foreground">{t("zapretExcludeDomains")}</span>
                  <span className="text-[11px] leading-snug text-muted-foreground">Домены-исключения (по одному в строке): к ним DPI-обход НЕ применяется — идут напрямую.</span>
                  <textarea
                    className="min-h-[100px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.exclude_domains ?? "")}
                    onChange={(e) => setStr("exclude_domains", e.target.value)}
                    placeholder="example.ru\\nvk.com"
                  />
                </label>''',
    "zapret exclude caption",
    guard='к ним DPI-обход НЕ применяется',
)
repl(
    '''                <label className="grid gap-1 text-muted-foreground">
                  {t("zapretForceDomains")}
                  <textarea
                    className="min-h-[80px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.force_domains ?? "")}
                    onChange={(e) => setStr("force_domains", e.target.value)}
                  />
                </label>''',
    '''                <label className="grid gap-1">
                  <span className="text-xs font-medium text-foreground">{t("zapretForceDomains")}</span>
                  <span className="text-[11px] leading-snug text-muted-foreground">Домены (по одному в строке), к которым DPI-обход применяется принудительно, даже если они не в общих списках.</span>
                  <textarea
                    className="min-h-[80px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.force_domains ?? "")}
                    onChange={(e) => setStr("force_domains", e.target.value)}
                    placeholder="youtube.com\\ndiscord.com"
                  />
                </label>''',
    "zapret force caption",
    guard='применяется принудительно, даже если',
)

if changed:
    f.write_text(t)
print("[patch-addon-settings-ui] ok")
PY
