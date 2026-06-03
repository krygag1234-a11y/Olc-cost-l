#!/usr/bin/env bash
# Replace bridge log with card-based UI (like split domains).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-bridge-cards-ui' "$MAIN_TSX" && { echo "[patch-bridge-cards-ui] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Marker
if 'olc-bridge-cards-ui' not in t:
    t = t.replace('function BridgesSettingsFields', '/* olc-bridge-cards-ui */\nfunction BridgesSettingsFields', 1)

# Replace bridges_conf <pre> log with card list
old_pre = '''      <pre className="max-h-[160px] overflow-auto rounded border border-border bg-background p-2 text-xs">
        {String(settings.bridges_conf ?? "").slice(-3000) || "(пусто)"}
      </pre>'''

new_cards = '''      <BridgeListCards 
        bridgesConf={String(settings.bridges_conf ?? "")} 
        onDelete={(fingerprint) => {
          setMsg("Удаление моста " + fingerprint + "...");
          fetch("/api/settings/bridges", {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: "delete_bridge", fingerprint }),
          }).then(res => {
            if (res.ok) {
              setMsg("Мост удалён, обновите конфиг");
              onReload && onReload();
            } else {
              setMsg("Ошибка удаления: HTTP " + res.status);
            }
          });
        }}
      />'''

if old_pre in t:
    t = t.replace(old_pre, new_cards, 1)

# Add BridgeListCards component before BridgesSettingsFields
component = r'''
function BridgeListCards({ bridgesConf, onDelete }: { bridgesConf: string; onDelete: (fp: string) => void }) {
  const lines = bridgesConf.split("\n").filter(l => l.trim().startsWith("Bridge"));
  const [statuses, setStatuses] = useState<Record<string, any>>({});

  useEffect(() => {
    const load = async () => {
      try {
        const res = await fetch("/api/bridges/status", { cache: "no-store" });
        if (res.ok) {
          const data = await res.json();
          const map: Record<string, any> = {};
          (data.active_bridges ?? []).forEach((b: any) => {
            if (b.fingerprint) map[b.fingerprint] = b.health;
          });
          setStatuses(map);
        }
      } catch (e) {}
    };
    load();
    const interval = setInterval(load, 20000);
    return () => clearInterval(interval);
  }, []);

  if (lines.length === 0) {
    return <div className="text-xs text-muted-foreground p-2 border border-border rounded">Мостов нет</div>;
  }

  return (
    <div className="max-h-[240px] overflow-y-auto space-y-1 border border-border rounded p-2">
      {lines.map((line, i) => {
        const parts = line.split(" ");
        const type = parts[1] ?? "?";
        const fp = parts.find(p => p.length === 40) ?? "";
        const health = statuses[fp];
        const failStreak = health?.fail_streak ?? 0;
        const lastStatus = health?.last_status ?? "unknown";
        const healthIcon = failStreak > 2 ? "✗" : failStreak > 0 ? "⚠" : "✓";
        const healthColor = failStreak > 2 ? "text-red-600" : failStreak > 0 ? "text-yellow-600" : "text-green-600";

        return (
          <div key={i} className="flex items-center gap-2 rounded bg-muted/30 p-2 text-xs hover:bg-muted/50">
            <span className={`font-bold ${healthColor}`}>{healthIcon}</span>
            <span className="font-mono text-primary">{type}</span>
            <span className="flex-1 font-mono text-[10px] opacity-60 truncate">{fp || line.slice(0, 60)}</span>
            <span className="text-[9px] opacity-40">{lastStatus}</span>
            <button
              type="button"
              onClick={() => fp && onDelete(fp)}
              className="text-destructive hover:text-destructive/80"
              title="Удалить мост"
            >
              🗑️
            </button>
          </div>
        );
      })}
    </div>
  );
}

'''

if 'function BridgeListCards' not in t:
    t = t.replace('function BridgesSettingsFields', component + 'function BridgesSettingsFields', 1)

p.write_text(t)
print("[patch-bridge-cards-ui] ok")
PY
