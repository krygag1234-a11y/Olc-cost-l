#!/usr/bin/env bash
# Sync global-randomization state across all three UI surfaces:
#   - App.globalRandomizationEnabled is the single source of truth
#   - SubscriptionRandomizationPanel becomes controlled (optimistic toggle -> App state)
#   - SelectiveRandomizationPanel + client-card buttons react instantly (no 2-5s polling lag)
# Fixes P2 UI-sync issues:
#   * client-card button locks with delay / doesn't unlock without reload
#   * selective-panel checkboxes ignore global mode
# Idempotent; run AFTER subscription-ui + selective-randomization-ui + randomization-ui-full.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-randomization-sync] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys
p = sys.argv[1]
import pathlib
f = pathlib.Path(p)
t = f.read_text()
changed = False

# --- 1. SubscriptionRandomizationPanel -> controlled by App state (optimistic) ---
sub_old = '''function SubscriptionRandomizationPanel({
  onClose,
}: {
  onClose?: () => void;
}) {
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(true);
  const [msg, setMsg] = useState("");

  useEffect(() => {
    void fetch("/api/settings/randomization/global", { cache: "no-store" })
      .then((r) => r.json())
      .then((b: { enabled?: boolean }) => {
        setEnabled(b.enabled ?? false);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  const toggle = async () => {
    const newVal = !enabled;
    const res = await fetch("/api/settings/randomization/global", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: newVal }),
    });
    if (res.ok) {
      setEnabled(newVal);
      setMsg("Сохранено");
    } else {
      setMsg(`Ошибка: HTTP ${res.status}`);
    }
  };'''

sub_new = '''function SubscriptionRandomizationPanel({
  onClose,
  globalEnabled,
  onGlobalChange,
}: {
  onClose?: () => void;
  globalEnabled?: boolean;
  onGlobalChange?: (v: boolean) => void;
}) {
  const enabled = globalEnabled ?? false;
  const loading = false;
  const [msg, setMsg] = useState("");

  const toggle = async () => {
    const newVal = !enabled;
    // optimistic: update shared App state immediately so client cards + selective panel react instantly
    onGlobalChange?.(newVal);
    const res = await fetch("/api/settings/randomization/global", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: newVal }),
    });
    if (res.ok) {
      setMsg("Сохранено");
    } else {
      onGlobalChange?.(enabled); // rollback on failure
      setMsg(`Ошибка: HTTP ${res.status}`);
    }
  };'''

if sub_new.split("\n")[7].strip() in t and "onGlobalChange?: (v: boolean) => void;" in t:
    print("[patch-randomization-sync] SubscriptionRandomizationPanel already controlled")
elif sub_old in t:
    t = t.replace(sub_old, sub_new, 1)
    changed = True
    print("[patch-randomization-sync] SubscriptionRandomizationPanel -> controlled")
else:
    print("[patch-randomization-sync] WARN: SubscriptionRandomizationPanel anchor not found")

# --- 2. Pass props at SubscriptionRandomizationPanel render site ---
sub_render_old = '''            {subscriptionRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SubscriptionRandomizationPanel />
              </div>
            )}'''
sub_render_new = '''            {subscriptionRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SubscriptionRandomizationPanel
                  globalEnabled={globalRandomizationEnabled}
                  onGlobalChange={setGlobalRandomizationEnabled}
                />
              </div>
            )}'''
if sub_render_new in t:
    print("[patch-randomization-sync] SubscriptionRandomizationPanel render already wired")
elif sub_render_old in t:
    t = t.replace(sub_render_old, sub_render_new, 1)
    changed = True
    print("[patch-randomization-sync] wired SubscriptionRandomizationPanel props")
else:
    print("[patch-randomization-sync] WARN: SubscriptionRandomizationPanel render anchor not found")

# --- 3. SelectiveRandomizationPanel accepts globalEnabled prop ---
sel_sig_old = 'function SelectiveRandomizationPanel() {'
sel_sig_new = '''function SelectiveRandomizationPanel({
  globalEnabled,
}: {
  globalEnabled?: boolean;
}) {'''
if 'function SelectiveRandomizationPanel({' in t:
    print("[patch-randomization-sync] SelectiveRandomizationPanel already parametrized")
elif sel_sig_old in t:
    t = t.replace(sel_sig_old, sel_sig_new, 1)
    changed = True
    print("[patch-randomization-sync] SelectiveRandomizationPanel accepts globalEnabled")
else:
    print("[patch-randomization-sync] WARN: SelectiveRandomizationPanel signature not found")

# --- 4. compute enabled = global || per-client ---
sel_enabled_old = '''            const enabled = c.randomization?.enabled ?? false;
            const randomizedID = c.randomization?.randomized_id || "";'''
sel_enabled_new = '''            const perClientEnabled = c.randomization?.enabled ?? false;
            const enabled = globalEnabled || perClientEnabled;
            const randomizedID = c.randomization?.randomized_id || "";'''
if 'const perClientEnabled = c.randomization?.enabled ?? false;' in t:
    print("[patch-randomization-sync] selective enabled-calc already patched")
elif sel_enabled_old in t:
    t = t.replace(sel_enabled_old, sel_enabled_new, 1)
    changed = True
    print("[patch-randomization-sync] selective enabled = global || per-client")
else:
    print("[patch-randomization-sync] WARN: selective enabled-calc anchor not found")

# --- 5. checkbox checked+disabled+label under global ---
sel_cb_old = '''                    <input
                      type="checkbox"
                      checked={enabled}
                      onChange={() => toggleRandomization(c.client_id, enabled)}
                      className="rounded"
                    />
                    <span className="text-xs">{enabled ? "On" : "Off"}</span>'''
sel_cb_new = '''                    <input
                      type="checkbox"
                      checked={enabled}
                      disabled={globalEnabled}
                      onChange={() => toggleRandomization(c.client_id, perClientEnabled)}
                      className={globalEnabled ? "rounded opacity-50 cursor-not-allowed" : "rounded"}
                    />
                    <span className="text-xs">{globalEnabled ? "ON (глобально)" : enabled ? "On" : "Off"}</span>'''
if 'disabled={globalEnabled}' in t and 'ON (глобально)' in t:
    print("[patch-randomization-sync] selective checkbox already global-aware")
elif sel_cb_old in t:
    t = t.replace(sel_cb_old, sel_cb_new, 1)
    changed = True
    print("[patch-randomization-sync] selective checkbox locks under global")
else:
    print("[patch-randomization-sync] WARN: selective checkbox anchor not found")

# --- 6. Pass globalEnabled at SelectiveRandomizationPanel render site ---
sel_render_old = '''            {selectiveRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SelectiveRandomizationPanel />
              </div>
            )}'''
sel_render_new = '''            {selectiveRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SelectiveRandomizationPanel globalEnabled={globalRandomizationEnabled} />
              </div>
            )}'''
if sel_render_new in t:
    print("[patch-randomization-sync] SelectiveRandomizationPanel render already wired")
elif sel_render_old in t:
    t = t.replace(sel_render_old, sel_render_new, 1)
    changed = True
    print("[patch-randomization-sync] wired SelectiveRandomizationPanel globalEnabled")
else:
    print("[patch-randomization-sync] WARN: SelectiveRandomizationPanel render anchor not found")

if changed:
    f.write_text(t)
print("[patch-randomization-sync] ok")
PY
