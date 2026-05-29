#!/usr/bin/env bash
# Replace FeatureSettingsModal hints with editable settings forms (GET/PUT /api/settings/).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'ComponentSettingsModal' "$MAIN_TSX" && { echo "[patch-panel-settings-forms] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old_modal = r'''function FeatureSettingsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  const info = FEATURE_SETTINGS_HINTS[feature];
  return (
    <Modal title={`Настройки: ${info.title}`} onClose={onClose}>
      <div className="space-y-2 p-4 text-sm text-muted-foreground">
        {info.lines.map((line) => (
          <p key={line}>{line}</p>
        ))}
      </div>
    </Modal>
  );
}'''

new_modal = r'''function FeatureSettingsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  return <ComponentSettingsModal feature={feature} onClose={onClose} />;
}

function ComponentSettingsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  const apiName = feature === "webtunnel" ? "bridges" : feature;
  const title = FEATURE_SETTINGS_HINTS[feature]?.title ?? feature;
  const [settings, setSettings] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const res = await fetch(`/api/settings/${apiName}`, { cache: "no-store" });
        const body = (await res.json()) as { settings?: Record<string, unknown> };
        if (!res.ok) throw new Error((body as { error?: string }).error || `HTTP ${res.status}`);
        if (!cancelled) setSettings(body.settings ?? {});
      } catch (e) {
        if (!cancelled) setMsg(String(e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [apiName]);

  const save = async () => {
    setSaving(true);
    setMsg("");
    try {
      const res = await fetch(`/api/settings/${apiName}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(settings),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error((err as { error?: string }).error || `HTTP ${res.status}`);
      }
      setMsg("Сохранено");
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const setStr = (key: string, value: string) => setSettings((s) => ({ ...s, [key]: value }));
  const setBool = (key: string, value: boolean) => setSettings((s) => ({ ...s, [key]: value }));

  return (
    <Modal title={`Настройки: ${title}`} onClose={onClose}>
      <div className="space-y-4 p-4 text-sm">
        {loading ? (
          <p className="text-muted-foreground">Загрузка…</p>
        ) : (
          <>
            {feature === "zapret" && (
              <>
                <label className="flex items-center gap-2 text-xs text-muted-foreground">
                  <input
                    type="checkbox"
                    checked={Boolean(settings.auto_sync)}
                    onChange={(e) => setBool("auto_sync", e.target.checked)}
                  />
                  Еженедельный auto-sync exclude списков
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Домены-исключения (direct, по строке)
                  <textarea
                    className="min-h-[100px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.exclude_domains ?? "")}
                    onChange={(e) => setStr("exclude_domains", e.target.value)}
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Домены только через zapret (по строке)
                  <textarea
                    className="min-h-[80px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.force_domains ?? "")}
                    onChange={(e) => setStr("force_domains", e.target.value)}
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  После сохранения: olc-feature zapret reload или olc-update
                </p>
              </>
            )}
            {feature === "tor" && (
              <>
                <p className="text-xs text-muted-foreground">SOCKS порт: {String(settings.socks_port ?? "9050")}</p>
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
                <p className="text-xs text-muted-foreground">
                  После сохранения применяется configure-tor-exit (может потребоваться перезапуск инстансов).
                </p>
              </>
            )}
            {feature === "split" && (
              <>
                <label className="grid gap-1 text-muted-foreground">
                  Доп. direct-домены (по строке)
                  <textarea
                    className="min-h-[100px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.custom_direct_domains ?? "")}
                    onChange={(e) => setStr("custom_direct_domains", e.target.value)}
                  />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Список panel/carrier hosts
                  <textarea
                    className="min-h-[80px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                    value={String(settings.panel_hosts ?? "")}
                    onChange={(e) => setStr("panel_hosts", e.target.value)}
                  />
                </label>
                <p className="text-xs text-muted-foreground">
                  RU-direct списков: {String(settings.ru_direct_count ?? "?")}. Полное обновление: olc-update
                </p>
              </>
            )}
            {(feature === "webtunnel" || feature === "bridges") && (
              <>
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
            )}
          </>
        )}
        {msg && <p className={`text-xs ${msg === "Сохранено" ? "text-emerald-400" : "text-destructive"}`}>{msg}</p>}
        <div className="flex justify-end gap-2">
          <button
            type="button"
            className="rounded-md border border-border px-3 py-2 text-sm hover:bg-muted"
            onClick={onClose}
          >
            Закрыть
          </button>
          <button
            type="button"
            disabled={loading || saving}
            className="rounded-md border border-primary bg-primary/20 px-3 py-2 text-sm text-primary disabled:opacity-50"
            onClick={() => void save()}
          >
            {saving ? "…" : "Сохранить"}
          </button>
        </div>
      </div>
    </Modal>
  );
}'''

if old_modal not in t:
    print("[patch-panel-settings-forms] FeatureSettingsModal block not found"); raise SystemExit(0)

t = t.replace(old_modal, new_modal, 1)

# Rename webtunnel label in hints if not already
t = t.replace('title: "WebTunnel"', 'title: "Мосты"', 1)

p.write_text(t)
print("[patch-panel-settings-forms] ok"); raise SystemExit(0)
PY
