#!/usr/bin/env bash
# UI: bridge status card in settings modal + quick rotate button.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-bridge-status-ui' "$MAIN_TSX" && { echo "[patch-bridge-status-ui] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Add marker
if 'olc-panel-bridge-status-ui' not in t:
    t = t.replace('import React, {', '/* olc-panel-bridge-status-ui */\nimport React, {', 1)

# Add BridgeStatusCard component before BridgesSettingsFields
component = r'''
function BridgeStatusCard({ onRotate }: { onRotate?: () => void }) {
  const [status, setStatus] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      try {
        const res = await fetch("/api/bridges/status", { cache: "no-store" });
        if (res.ok) {
          setStatus(await res.json());
        }
      } catch (e) {
        console.error("bridge status fetch failed", e);
      } finally {
        setLoading(false);
      }
    };
    load();
    const interval = setInterval(load, 15000);
    return () => clearInterval(interval);
  }, []);

  if (loading) return <div className="text-xs text-muted-foreground">Загрузка статуса мостов...</div>;
  if (!status) return null;

  const torOk = status.tor_ok ?? false;
  const activeBridges = (status.active_bridges ?? []) as any[];
  const monitorFails = status.monitor_fails ?? 0;

  return (
    <div className="rounded border border-border p-3 space-y-2 text-xs">
      <div className="flex items-center justify-between">
        <div className="font-medium">Статус подключения</div>
        <div className={`flex items-center gap-1 ${torOk ? "text-green-600" : "text-red-600"}`}>
          <span>{torOk ? "●" : "○"}</span>
          <span>{torOk ? "Tor работает" : "Tor недоступен"}</span>
        </div>
      </div>
      {monitorFails > 0 && (
        <div className="text-yellow-600">
          Обнаружены проблемы ({monitorFails} попытки). Может потребоваться ротация мостов.
        </div>
      )}
      <div className="text-muted-foreground">
        Активных мостов: {activeBridges.length} | Пул: {status.pool_size ?? 0}
      </div>
      {activeBridges.length > 0 && (
        <details className="text-muted-foreground">
          <summary className="cursor-pointer hover:text-foreground">Показать активные мосты</summary>
          <div className="mt-2 space-y-1 pl-2">
            {activeBridges.slice(0, 5).map((b, i) => {
              const health = b.health as any;
              const failStreak = health?.fail_streak ?? 0;
              const lastStatus = health?.last_status ?? "unknown";
              return (
                <div key={i} className="flex items-center gap-2 font-mono text-[10px]">
                  <span className={failStreak > 2 ? "text-red-600" : "text-green-600"}>
                    {failStreak > 2 ? "✗" : "✓"}
                  </span>
                  <span>{b.type}</span>
                  <span className="opacity-60">{b.fingerprint?.substring(0, 8)}</span>
                  <span className="opacity-40">{lastStatus}</span>
                </div>
              );
            })}
          </div>
        </details>
      )}
      {onRotate && (
        <button
          type="button"
          className="w-full rounded border border-primary px-2 py-1 text-primary hover:bg-primary/10"
          onClick={onRotate}
        >
          Быстрая ротация мостов
        </button>
      )}
    </div>
  );
}

'''

if 'function BridgeStatusCard' not in t:
    t = t.replace('function BridgesSettingsFields', component + 'function BridgesSettingsFields', 1)

# Add status card to BridgesSettingsFields
old_start = '''  return (
    <>
      <p className="text-xs text-muted-foreground">
        Пул: obfs4 {ps.obfs4 ?? 0}, webtunnel {ps.webtunnel ?? 0}'''

new_start = '''  const handleRotate = async () => {
    setMsg("Запуск ротации мостов...");
    try {
      const res = await fetch("/api/settings/bridges", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "rotate_bridges" }),
      });
      if (res.ok) {
        setMsg("Ротация запущена");
        onReload && (await onReload());
      } else {
        setMsg(`Ошибка: HTTP ${res.status}`);
      }
    } catch (e: any) {
      setMsg(`Ошибка: ${e.message}`);
    }
  };

  return (
    <>
      <BridgeStatusCard onRotate={handleRotate} />
      <p className="text-xs text-muted-foreground">
        Пул: obfs4 {ps.obfs4 ?? 0}, webtunnel {ps.webtunnel ?? 0}'''

if old_start in t and 'BridgeStatusCard' not in t.split('function BridgesSettingsFields')[1].split('return (')[1][:500]:
    t = t.replace(old_start, new_start, 1)

p.write_text(t)
print("[patch-bridge-status-ui] ok")
PY
