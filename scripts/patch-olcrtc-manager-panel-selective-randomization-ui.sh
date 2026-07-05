#!/usr/bin/env bash
# Selective Randomization UI: добавляет секцию в главный экран с toggle per-client
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'SelectiveRandomizationPanel' "$MAIN_TSX" && {
  echo "[patch-selective-randomization-ui] already applied"
  exit 0
}

# Use python3 on Linux, py on Windows
PYTHON_CMD="python3"
command -v python3 >/dev/null 2>&1 || PYTHON_CMD="py"

$PYTHON_CMD - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# === 1. Add SelectiveRandomizationPanel component before App ===
anchor = 'function App()'
if anchor in t and 'SelectiveRandomizationPanel' not in t:
    component = '''
function SelectiveRandomizationPanel() {
  const [clients, setClients] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [msg, setMsg] = useState("");

  const loadClients = () => {
    setLoading(true);
    fetch("/api/clients/", { cache: "no-store" })
      .then((r) => r.json())
      .then((data: any) => {
        setClients(data.clients || []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  };

  useEffect(() => {
    loadClients();
  }, []);

  const toggleRandomization = async (clientID: string, currentEnabled: boolean) => {
    const res = await fetch(`/api/clients/${encodeURIComponent(clientID)}/randomization`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: !currentEnabled }),
    });
    if (res.ok) {
      setMsg(`Рандомизация ${!currentEnabled ? "включена" : "отключена"} для ${clientID}`);
      loadClients();
    } else {
      setMsg(`Ошибка: HTTP ${res.status}`);
    }
  };

  return (
    <div className="space-y-3 text-sm">
      <div className="font-medium">Выборочная рандомизация</div>
      <p className="text-xs text-muted-foreground">
        Настройте рандомизацию URL для каждого клиента индивидуально
      </p>
      {loading ? (
        <p className="text-xs text-muted-foreground">Загрузка...</p>
      ) : clients.length === 0 ? (
        <p className="text-xs text-muted-foreground">Нет клиентов</p>
      ) : (
        <div className="space-y-2 max-h-60 overflow-y-auto">
          {clients.map((c: any) => {
            const enabled = c.randomization?.enabled ?? false;
            const randomizedID = c.randomization?.randomized_id || "";
            return (
              <div key={c.client_id} className="border border-border rounded p-2 space-y-1">
                <div className="flex items-center justify-between">
                  <div className="text-xs font-medium truncate flex-1">{c.client_id}</div>
                  <label className="flex items-center gap-1">
                    <input
                      type="checkbox"
                      checked={enabled}
                      onChange={() => toggleRandomization(c.client_id, enabled)}
                      className="rounded"
                    />
                    <span className="text-xs">{enabled ? "On" : "Off"}</span>
                  </label>
                </div>
                {enabled && randomizedID && (
                  <div className="text-xs text-muted-foreground truncate">
                    Hash: {randomizedID}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
      {msg && <p className="text-xs text-amber-600">{msg}</p>}
    </div>
  );
}

'''
    t = t.replace(anchor, component + anchor, 1)
    print("[patch-selective-randomization-ui] SelectiveRandomizationPanel component added")

# === 2. Add state for selectiveRandomizationOpen ===
state_anchor = 'const [subscriptionRandomizationOpen, setSubscriptionRandomizationOpen] = useState(false);'
if state_anchor in t and 'selectiveRandomizationOpen' not in t:
    new_state = state_anchor + '\n  const [selectiveRandomizationOpen, setSelectiveRandomizationOpen] = useState(false);'
    t = t.replace(state_anchor, new_state, 1)
    print("[patch-selective-randomization-ui] selectiveRandomizationOpen state added")

# === 3. Add link in main UI after SubscriptionRandomization section ===
settings_anchor = '<MainSettingsAutodetectLink'
if settings_anchor in t and 'Выборочная рандомизация' not in t:
    selective_link = '''            <div className="flex items-center justify-between border-b border-border py-2">
              <div>
                <div className="text-sm font-medium">Выборочная рандомизация</div>
                <div className="text-xs text-muted-foreground">Индивидуальные настройки рандомизации для каждого клиента</div>
              </div>
              <button
                type="button"
                className="rounded bg-blue-500/10 border border-blue-500/30 px-2 py-1 text-xs text-blue-600 hover:bg-blue-500/20 transition-colors"
                onClick={() => setSelectiveRandomizationOpen(!selectiveRandomizationOpen)}
              >
                {selectiveRandomizationOpen ? "Скрыть" : "Настроить"}
              </button>
            </div>
            {selectiveRandomizationOpen && (
              <div className="border-l-2 border-primary/30 pl-3">
                <SelectiveRandomizationPanel />
              </div>
            )}
            '''
    t = t.replace(settings_anchor, selective_link + settings_anchor, 1)
    print("[patch-selective-randomization-ui] Selective Randomization link added to main UI")

p.write_text(t)
print("[patch-selective-randomization-ui] ok")
PY
