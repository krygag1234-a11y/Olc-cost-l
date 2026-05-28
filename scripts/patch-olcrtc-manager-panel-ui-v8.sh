#!/usr/bin/env bash
# UI v8: inline autodetect panel, nfqws editable, collapsible "Сеть и обход".
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-v8' "$MAIN_TSX" && { echo "[patch-panel-ui-v8] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

t = t.replace("/* olc-panel-ui-v7 */", "/* olc-panel-ui-v8 */", 1) if "olc-panel-ui-v7" in t else t.replace(
    "import React, {", "/* olc-panel-ui-v8 */\nimport React, {", 1
)

# 1) Inline autodetect panel in main settings (no separate modal from this button)
old_main = '''function MainSettingsAutodetectLink() {
  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Автодетектор</div>
      <p className="text-xs text-muted-foreground">Периодически ищет ошибки в логах и состоянии сервисов.</p>
      <button
        type="button"
        className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted"
        onClick={() => window.dispatchEvent(new CustomEvent("olc-open-autodetect-settings"))}
      >
        Настройки уведомлений автодетектора
      </button>
    </section>
  );
}'''

new_main = '''function MainSettingsAutodetectLink({
  expanded,
  onToggle,
}: {
  expanded: boolean;
  onToggle: () => void;
}) {
  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Автодетектор</div>
      <p className="text-xs text-muted-foreground">Периодически ищет ошибки в логах и состоянии сервисов.</p>
      <button type="button" className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted" onClick={onToggle}>
        Настройки уведомлений автодетектора
      </button>
      {expanded && (
        <div className="rounded-md border border-dashed border-border bg-card p-3">
          <AutodetectNotificationSettingsPanel />
        </div>
      )}
    </section>
  );
}'''

if old_main in t:
    t = t.replace(old_main, new_main, 1)

# Remove old standalone autodetect modal if still present
auto_modal = '''function AutodetectNotificationSettingsModal({ onClose }: { onClose: () => void }) {
  return (
    <Modal title="Автодетектор" onClose={onClose}>
      <div className="p-4">
        <AutodetectNotificationSettingsPanel onClose={onClose} />
      </div>
    </Modal>
  );
}

'''
t = t.replace(auto_modal, "", 1)

# App state/listener cleanup and inline toggle wiring
t = t.replace(
    '  const [showSettings, setShowSettings] = useState(false);\n  const [autodetectSettingsOpen, setAutodetectSettingsOpen] = useState(false);',
    '  const [showSettings, setShowSettings] = useState(false);\n  const [showAutodetectInline, setShowAutodetectInline] = useState(false);',
    1,
)

t = t.replace(
    '''  useEffect(() => {
    const h = () => setAutodetectSettingsOpen(true);
    window.addEventListener("olc-open-autodetect-settings", h);
    return () => window.removeEventListener("olc-open-autodetect-settings", h);
  }, []);

''',
    "",
    1,
)

t = t.replace(
    '''      {autodetectSettingsOpen && <AutodetectNotificationSettingsModal onClose={() => setAutodetectSettingsOpen(false)} />}
      {showSettings && (''',
    '''      {showSettings && (''',
    1,
)

t = t.replace(
    '            <MainSettingsAutodetectLink />',
    '            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />',
)

t = t.replace(
    '''  const openSettings = async () => {
    setShowSettings(true);
    setNotice("");''',
    '''  const openSettings = async () => {
    setShowSettings(true);
    setShowAutodetectInline(false);
    setNotice("");''',
    1,
)

t = t.replace(
    'onClick={() => setShowSettings(false)}',
    'onClick={() => { setShowAutodetectInline(false); setShowSettings(false); }}',
    1,
)

# 2) Editable nfqws config + warning
t = t.replace(
    '''                <details className="text-xs">
                  <summary className="cursor-pointer text-muted-foreground">Ядро nfqws (config)</summary>
                  <pre className="mt-1 max-h-40 overflow-auto rounded border border-border bg-background p-2 font-mono text-[10px]">{String(settings.nfqws_config ?? "—")}</pre>
                </details>''',
    '''                <label className="grid gap-1 text-muted-foreground">
                  Ядро nfqws (config)
                  <textarea
                    className="min-h-[140px] rounded-md border border-border bg-background p-2 font-mono text-[10px]"
                    value={String(settings.nfqws_config ?? "")}
                    onChange={(e) => setStr("nfqws_config", e.target.value)}
                  />
                </label>
                <p className="text-xs text-amber-400">
                  Внимание: это низкоуровневый конфиг zapret/nfqws. Если не уверены, лучше не менять.
                </p>''',
    1,
)

# 3) Collapsible "Сеть и обход" with persisted state
if "const [collapsed, setCollapsed]" not in t:
    t = t.replace(
        '  const [busy, setBusy] = useState<FeatureName | null>(null);\n  const [err, setErr] = useState<string>("");',
        '''  const [busy, setBusy] = useState<FeatureName | null>(null);
  const [err, setErr] = useState<string>("");
  const [collapsed, setCollapsed] = useState<boolean>(() => {
    try {
      return localStorage.getItem("olc-network-bypass-collapsed") === "1";
    } catch {
      return false;
    }
  });''',
        1,
    )

if "olc-network-bypass-collapsed" not in t:
    t = t.replace(
        '''  useEffect(() => {
    void load();
    const onChange = () => void load();
    window.addEventListener("olc-features-changed", onChange);
    return () => window.removeEventListener("olc-features-changed", onChange);
  }, []);''',
        '''  useEffect(() => {
    void load();
    const onChange = () => void load();
    window.addEventListener("olc-features-changed", onChange);
    return () => window.removeEventListener("olc-features-changed", onChange);
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem("olc-network-bypass-collapsed", collapsed ? "1" : "0");
    } catch {
      // ignore localStorage failures
    }
  }, [collapsed]);''',
        1,
    )

if '{collapsed ? "Развернуть" : "Свернуть"}' not in t:
    t = t.replace(
        '''        </div>
      </div>''',
        '''        </div>
        <button type="button" className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs hover:bg-muted" onClick={() => setCollapsed((v) => !v)}>
          {collapsed ? "Развернуть" : "Свернуть"}
        </button>
      </div>''',
        1,
    )

t = t.replace("{data && (", "{!collapsed && data && (", 1)

p.write_text(t)
print("[patch-panel-ui-v8] ok"); print(0); raise SystemExit(0)
PY
