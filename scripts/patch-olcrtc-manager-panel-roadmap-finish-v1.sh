#!/usr/bin/env bash
# ROADMAP backlog UI: strategy select, cidr toggle, errors drawer, update toast, confirms, perf.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-roadmap-finish-v1' "$MAIN_TSX" && { echo "[patch-panel-roadmap-finish-v1] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
t = p.read_text()

if '/* olc-roadmap-finish-v1 */' not in t:
    t = t.replace('/* olc-components-jobs-ui-ttl */', '/* olc-components-jobs-ui-ttl */\n/* olc-roadmap-finish-v1 */', 1)

# --- ErrorsSummaryButton: warning+, matched lines ---
old_err = '''  const errors = items.filter((n) => n.severity === "error");'''
new_err = '''  const issues = items.filter((n) => n.severity === "error" || n.severity === "warning");
  const errors = issues;'''
if old_err in t and 'n.severity === "warning"' not in t.split('ErrorsSummaryButton')[1][:800]:
    t = t.replace(old_err, new_err, 1)

old_li = '''            {errors.map((n) => (
              <li key={n.id} className="rounded border border-border p-2">
                <div className="font-medium text-destructive">{n.title}</div>
                <p className="text-xs text-muted-foreground">{n.meaning}</p>
                {n.fixes && n.fixes.length > 0 && (
                  <ul className="mt-1 list-disc pl-4 text-xs">
                    {n.fixes.map((f, i) => (
                      <li key={i}>{f}</li>
                    ))}
                  </ul>
                )}
              </li>
            ))}'''
new_li = '''            {errors.map((n) => (
              <li key={n.id} className="rounded border border-border p-2">
                <div className="font-medium text-destructive">{n.title}</div>
                <p className="text-xs text-muted-foreground">{n.meaning}</p>
                {Array.isArray((n as { matched_lines?: string[] }).matched_lines) &&
                  (n as { matched_lines?: string[] }).matched_lines!.length > 0 && (
                  <pre className="mt-1 max-h-24 overflow-auto rounded bg-muted p-1 font-mono text-[10px]">
                    {(n as { matched_lines?: string[] }).matched_lines!.join("\\n")}
                  </pre>
                )}
                {n.fixes && n.fixes.length > 0 && (
                  <ul className="mt-1 list-disc pl-4 text-xs">
                    {n.fixes.map((f, i) => (
                      <li key={i}>{f}</li>
                    ))}
                  </ul>
                )}
              </li>
            ))}
            <p className="text-xs">
              <button type="button" className="text-primary underline" onClick={() => { setOpen(false); window.dispatchEvent(new Event("olc-open-autodetect-settings")); }}>
                Настройки автодетектора
              </button>
            </p>'''
if old_li in t:
    t = t.replace(old_li, new_li, 1)

# --- Zapret: strategy select + reinstall ---
zap_hint = '''                <p className="text-xs text-muted-foreground">
                  Стратегия: {String(settings.strategy ?? "—")} · nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}
                </p>'''
zap_fields = '''                <label className="grid gap-1 text-muted-foreground">
                  Стратегия zapret
                  <select
                    className="h-9 rounded-md border border-border bg-background px-2 text-sm"
                    value={String(settings.strategy_current ?? settings.strategy ?? "olcrtc-minimal")}
                    onChange={(e) => setStr("strategy_id", e.target.value)}
                  >
                    {((settings.strategy_presets as { id: string; label: string }[]) ?? []).map((p) => (
                      <option key={p.id} value={p.id}>{p.label}</option>
                    ))}
                  </select>
                </label>
                <p className="text-xs text-amber-600">
                  Перезапуск zapret кратко прерывает DPI на direct-трафике.
                </p>
                <button
                  type="button"
                  className="rounded border border-destructive px-2 py-1 text-xs text-destructive"
                  onClick={() => {
                    if (!window.confirm("Переустановить zapret? 5–15 мин, панель может перезагружать инстансы.")) return;
                    void fetch("/api/settings/zapret", {
                      method: "PUT",
                      headers: { "Content-Type": "application/json" },
                      body: JSON.stringify({ reinstall: true }),
                    }).then(() => setMsg("Переустановка zapret запущена в фоне"));
                  }}
                >
                  Переустановить zapret
                </button>
                <p className="text-xs text-muted-foreground">
                  nfqws: {settings.zapret_full ? "да" : "нет"} · community lists: {settings.community_sync ? "да" : "нет"}
                </p>'''
if zap_hint in t:
    t = t.replace(zap_hint, zap_fields, 1)

# --- Split: cidr_only checkbox ---
split_cidr = '''                <p className="text-xs text-muted-foreground">
                  RU-direct: {String(settings.ru_direct_count ?? "?")} · CIDR: {String(settings.direct_cidrs_file ?? "—")} · только CIDR: {settings.cidr_only ? "да" : "нет"}
                </p>'''
split_cidr_ui = '''                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={Boolean(settings.cidr_only)}
                    onChange={(e) => setBool("cidr_only", e.target.checked)}
                  />
                  Только CIDR (без CDN /32) — меньше 404 на nginx edge
                </label>
                <p className="text-xs text-muted-foreground">
                  RU-direct: {String(settings.ru_direct_count ?? "?")} · файл: {String(settings.direct_cidrs_file ?? "—")}
                </p>'''
if split_cidr in t:
    t = t.replace(split_cidr, split_cidr_ui, 1)

# --- Update toast (persistent) ---
if 'function UpdateAvailableToast' not in t:
    toast = r'''
function UpdateAvailableToast() {
  const [show, setShow] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const check = useCallback(async () => {
    try {
      const res = await fetch("/api/updates/check", { cache: "no-store" });
      if (!res.ok) return;
      const b = (await res.json()) as { available?: boolean };
      if (b.available && !dismissed) setShow(true);
    } catch { /* ignore */ }
  }, [dismissed]);
  useEffect(() => {
    void check();
    const id = window.setInterval(() => void check(), 6 * 60 * 60 * 1000);
    return () => window.clearInterval(id);
  }, [check]);
  if (!show) return null;
  return (
    <div className="fixed bottom-4 right-4 z-50 flex max-w-sm items-start gap-2 rounded-lg border border-primary bg-background p-3 shadow-lg">
      <span className="text-sm">Доступно обновление с GitHub</span>
      <button type="button" className="text-xs text-primary underline" onClick={() => window.dispatchEvent(new Event("olc-open-project-modal"))}>
        Открыть
      </button>
      <button type="button" className="ml-auto text-muted-foreground" onClick={() => { setDismissed(true); setShow(false); }} aria-label="Закрыть">
        ✕
      </button>
    </div>
  );
}
'''
    t = t.replace('function App() {', toast + '\nfunction App() {', 1)
    if '<UpdateAvailableToast />' not in t:
        t = t.replace(
            '  return (\n    <div className="min-h-screen',
            '  return (\n    <>\n    <UpdateAvailableToast />\n    <div className="min-h-screen',
            1,
        )
    if '<UpdateAvailableToast />' in t and '</>\n  );' not in t.split('function App')[1][-800:]:
        t = t.replace(
            '      )}\n    </div>\n  );\n}\n\ncreateRoot(document.getElementById("root")!)',
            '      )}\n    </div>\n    </>\n  );\n}\n\ncreateRoot(document.getElementById("root")!)',
            1,
        )

# --- Capabilities refresh every 30s ---
if 'capabilitiesRefresh30s' not in t and 'function useCapabilities()' in t:
    t = t.replace(
        '''    return () => {
      cancelled = true;
    };
  }, []);
  const visible = (name: FeatureName) => {''',
        '''    const iv = window.setInterval(() => {
      if (!cancelled) void (async () => {
        try {
          const res = await fetch("/api/capabilities", { cache: "no-store" });
          if (!res.ok) return;
          const body = (await res.json()) as Capabilities;
          if (!cancelled) setCaps(body);
        } catch { /* ignore */ }
      })();
    }, 30_000);
    return () => {
      cancelled = true;
      window.clearInterval(iv);
    };
  }, []); /* capabilitiesRefresh30s */
  const visible = (name: FeatureName) => {''',
        1,
    )

# --- Metrics: slower poll when tab hidden ---
if 'metricsTabHidden' not in t and 'setInterval' in t and '/api/metrics' in t:
    t = t.replace(
        'const id = window.setInterval(load, 5000);',
        'const tick = () => { if (document.visibilityState !== "hidden") void load(); };\n    const id = window.setInterval(tick, 15000); /* metricsTabHidden */',
        1,
    )

# --- Bridges uninstall: confirm split ---
if 'bridges-uninstall-split-hint' not in t and 'c.id === "bridges"' in t:
    t = t.replace(
        'onClick={() => void run(c.id, "uninstall")}',
        'onClick={() => {\n                        if (c.id === "bridges" && !window.confirm("Отключить мосты? Рекомендуется также отключить Split (Tor PT).")) return;\n                        void run(c.id, "uninstall");\n                      }}',
        1,
    )

# --- Settings hub links ---
if 'olc-open-notification-settings' not in t.split('function SettingsModal')[1][:4000] if 'function SettingsModal' in t else True:
    needle = 'function SettingsModal'
    if needle in t:
        idx = t.find(needle)
        chunk = t[idx:idx+5000]
        if 'Автодетектор ошибок' not in chunk:
            t = t.replace(
                '<DialogTitle>Настройки</DialogTitle>',
                '''<DialogTitle>Настройки</DialogTitle>
            <p className="text-xs text-muted-foreground">
              <button type="button" className="text-primary underline" onClick={() => window.dispatchEvent(new Event("olc-open-notification-settings"))}>
                Уведомления и автодетектор
              </button>
            </p>''',
                1,
            )

p.write_text(t)
print("[patch-panel-roadmap-finish-v1] ok")
PY
