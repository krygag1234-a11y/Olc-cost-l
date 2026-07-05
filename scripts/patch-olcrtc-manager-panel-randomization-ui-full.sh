#!/usr/bin/env bash
# Subscription Randomization UI: Full integration (Client Card button + hash display + global state)
# Depends on: patch-olcrtc-manager-subscription-randomization.sh, patch-olcrtc-manager-subscription-api.sh
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

grep -q 'globalRandomization.*Global subscription ID randomization' "$MAIN_TSX" && {
  echo "[patch-randomization-ui-full] already applied"
  exit 0
}

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path
import re

p = Path(sys.argv[1])
t = p.read_text(encoding='utf-8')

# === 1. Add i18n keys for globalRandomization ===
# RU locale
ru_anchor = '    refreshInterval: "Интервал обновления",'
if ru_anchor in t and 'globalRandomization' not in t:
    t = t.replace(
        ru_anchor,
        ru_anchor + '\n    globalRandomization: "Глобальная рандомизация subscription ID",',
        1
    )
    print("[patch-randomization-ui-full] added RU i18n key")

# EN locale
en_anchor = '    refreshInterval: "Refresh interval",'
if en_anchor in t:
    t = t.replace(
        en_anchor,
        en_anchor + '\n    globalRandomization: "Global subscription ID randomization",',
        1
    )
    print("[patch-randomization-ui-full] added EN i18n key")

# === 2. Add randomization field to ClientState type ===
if 'type ClientState = {' in t and 'randomization?: {' not in t:
    client_state_anchor = '''  locations: LocationState[];
};'''
    client_state_insert = '''  locations: LocationState[];
  randomization?: {
    enabled: boolean;
    randomized_id?: string;
  };
};'''
    t = t.replace(client_state_anchor, client_state_insert, 1)
    print("[patch-randomization-ui-full] added ClientState.randomization field")

# === 3. Add globalRandomizationEnabled state variable ===
password_form_state = '  const [passwordForm, setPasswordForm] = useState({ current: "", next: "", repeat: "" });'
if password_form_state in t and 'globalRandomizationEnabled' not in t:
    t = t.replace(
        password_form_state,
        password_form_state + '\n  const [globalRandomizationEnabled, setGlobalRandomizationEnabled] = useState(false);',
        1
    )
    print("[patch-randomization-ui-full] added globalRandomizationEnabled state")

# === 4. Load global randomization state in loadSettings ===
# Find the loadSettings function and add API call after settingsForm update
settings_anchor = '''      subscription_path: body.subscription_path,
      refresh: body.refresh ?? "",
    });'''

if settings_anchor in t and 'Load global randomization state' not in t:
    load_global_rand = '''      subscription_path: body.subscription_path,
      refresh: body.refresh ?? "",
    });

    // Load global randomization state
    try {
      const randRes = await request("/api/settings/randomization/global", { cache: "no-store" });
      const randBody = (await randRes.json()) as { enabled: boolean };
      setGlobalRandomizationEnabled(randBody.enabled ?? false);
    } catch {
      setGlobalRandomizationEnabled(false);
    }'''
    t = t.replace(settings_anchor, load_global_rand, 1)
    print("[patch-randomization-ui-full] added global randomization state loading")

# === 5. Add toggleRandomization handler ===
# Insert before copySubscription function
copy_sub_anchor = '  const copySubscription = (clientID: string) =>'
if copy_sub_anchor in t and 'toggleRandomization' not in t:
    toggle_handler = '''  const toggleRandomization = (clientID: string, currentlyEnabled: boolean) =>
    runAction(async () => {
      const endpoint = currentlyEnabled ? "disable" : "enable";
      await request(`/api/clients/${clientID}/randomization/${endpoint}`, { method: "POST" });
      await loadState();
    }, currentlyEnabled ? "Randomization disabled" : "Randomization enabled");

  const copySubscription = (clientID: string) =>'''
    t = t.replace(copy_sub_anchor, toggle_handler, 1)
    print("[patch-randomization-ui-full] added toggleRandomization handler")

# === 6. Add randomized_id display under client_id ===
# Find the client card rendering section
client_summary_anchor = '''                        <span className="mt-1 block text-xs text-muted-foreground">
                          {clientSummary(client, running)}
                        </span>'''

if client_summary_anchor in t and '🔒' not in t:
    randomized_display = '''                        {globalRandomizationEnabled && client.randomization?.randomized_id && (
                          <span className="mt-1 block truncate text-xs text-muted-foreground">
                            🔒 {client.randomization.randomized_id}
                          </span>
                        )}
                        <span className="mt-1 block text-xs text-muted-foreground">
                          {clientSummary(client, running)}
                        </span>'''
    t = t.replace(client_summary_anchor, randomized_display, 1)
    print("[patch-randomization-ui-full] added randomized_id display")

# === 7. Add per-client randomization button (🎲 ON/OFF) ===
# Insert after "Логи" button, before edit button
logs_button_anchor = '''                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        onClick={() => openClientLogs(client)}
                      >
                        <Terminal className="h-4 w-4" />
                        Логи
                      </button>'''

if logs_button_anchor in t and '🎲' not in t:
    randomize_button = '''                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        onClick={() => openClientLogs(client)}
                      >
                        <Terminal className="h-4 w-4" />
                        Логи
                      </button>
                      <button
                        className={`inline-flex h-8 items-center gap-2 rounded-md border px-2 text-sm disabled:opacity-60 ${
                          client.randomization?.enabled || globalRandomizationEnabled
                            ? "border-green-500/40 bg-green-500/10 text-green-600 hover:bg-green-500/20"
                            : "border-border hover:bg-muted"
                        }`}
                        disabled={busy || globalRandomizationEnabled}
                        onClick={() => toggleRandomization(client.client_id, client.randomization?.enabled ?? false)}
                        title={
                          globalRandomizationEnabled
                            ? "Global randomization enabled (disable global first)"
                            : client.randomization?.enabled
                            ? "Randomization ON — click to disable"
                            : "Randomization OFF — click to enable"
                        }
                      >
                        🎲 {client.randomization?.enabled || globalRandomizationEnabled ? "ON" : "OFF"}
                      </button>'''
    t = t.replace(logs_button_anchor, randomize_button, 1)
    print("[patch-randomization-ui-full] added per-client randomization button")

p.write_text(t, encoding='utf-8')
print("[patch-randomization-ui-full] ok")
PY
