#!/usr/bin/env bash
# Subscription Randomization UI: Settings panel для global toggle
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'SubscriptionRandomizationPanel' "$MAIN_TSX" && {
  echo "[patch-subscription-ui] already applied"
  exit 0
}

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path
import re

p = Path(sys.argv[1])
t = p.read_text()

# === 1. Add SubscriptionRandomizationPanel component before App function ===
anchor = 'function App()'
if anchor in t and 'SubscriptionRandomizationPanel' not in t:
    component = '''
function SubscriptionRandomizationPanel({
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
  };

  return (
    <div className="space-y-3 text-sm">
      <div className="font-medium">Глобальная рандомизация подписок</div>
      <p className="text-xs text-muted-foreground">
        Включает защиту от enumeration для всех клиентов. Direct ID блокируется, работает только через hash.
      </p>
      {loading ? (
        <p className="text-xs text-muted-foreground">Загрузка...</p>
      ) : (
        <label className="flex items-center gap-2 text-xs cursor-pointer">
          <input
            type="checkbox"
            checked={enabled}
            onChange={() => void toggle()}
            className="cursor-pointer transition-transform hover:scale-110"
          />
          <span className={enabled ? "text-amber-600 font-medium transition-colors" : "transition-colors"}>
            Включить глобальную рандомизацию
          </span>
        </label>
      )}
      {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
      {onClose && (
        <button type="button" className="rounded border border-border px-3 py-1 text-xs" onClick={onClose}>
          Закрыть
        </button>
      )}
    </div>
  );
}

'''
    t = t.replace(anchor, component + anchor, 1)
    print("[patch-subscription-ui] SubscriptionRandomizationPanel component added")

# === 2. Add state for subscriptionRandomizationOpen (BEFORE using it) ===
state_anchor = 'const [showAutodetectInline, setShowAutodetectInline] = useState(false);'
if state_anchor in t and 'subscriptionRandomizationOpen' not in t:
    new_state = state_anchor + '\n  const [subscriptionRandomizationOpen, setSubscriptionRandomizationOpen] = useState(false);'
    t = t.replace(state_anchor, new_state, 1)
    print("[patch-subscription-ui] subscriptionRandomizationOpen state added")

# === 3. Add link to Subscription Randomization in main Settings UI ===
# Find where AutodetectNotificationSettingsPanel link is placed
settings_anchor = '<MainSettingsAutodetectLink'
if settings_anchor in t and 'Subscription Randomization' not in t:
    # Add before AutodetectNotificationSettingsPanel link
    subscription_link = '''            <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Subscription Randomization</div>
                <div className="text-xs text-muted-foreground">Защита от enumeration через HMAC-SHA256 hash</div>
              </div>
              <button
                type="button"
                className="rounded bg-amber-500/10 border border-amber-500/30 px-2 py-1 text-xs text-amber-600 hover:bg-amber-500/20 transition-colors"
                onClick={() => setSubscriptionRandomizationOpen(!subscriptionRandomizationOpen)}
              >
                {subscriptionRandomizationOpen ? "Скрыть" : "Настроить"}
              </button>
            </div>
            {subscriptionRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SubscriptionRandomizationPanel />
              </div>
            )}
            '''
    t = t.replace(settings_anchor, subscription_link + settings_anchor, 1)
    print("[patch-subscription-ui] Subscription Randomization link added to Settings UI")

p.write_text(t)
print("[patch-subscription-ui] ok")
PY
