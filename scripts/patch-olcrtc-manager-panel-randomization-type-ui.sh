#!/usr/bin/env bash
# Olc-cost-l UI (Этап 2 эпика «Типы рандомизации»): выбор ТИПА рандомизации.
#   - мини-модалка RandTypeModal на кнопке 🎲 карточки клиента: выбор тип1/тип2;
#     «✕»/фон = закрыть БЕЗ включения (никакого ложного перещёлкивания в ON);
#   - обязательность типа: включить рандомизацию можно ТОЛЬКО выбрав тип;
#   - метка типа на карточке (ON · Т1/Т2);
#   - глобальный селектор типа (радио тип1/тип2) + подсветка секции;
#   - тип на строках «Выборочная рандомизация» (backend по умолчанию тип1).
# Backend уже поддерживает rand_type (subscription-randomization/-api).
# Idempotent. Target: main.tsx. Run ПОСЛЕ randomization-sync + client-access-ui.
set -euo pipefail
MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-randomization-type-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def rep(old, new, tag):
    global t, changed
    if new in t:
        print(f"[rand-type-ui] {tag}: already applied"); return
    if old not in t:
        print(f"[rand-type-ui] WARN {tag}: anchor not found"); return
    t = t.replace(old, new, 1); changed = True
    print(f"[rand-type-ui] {tag}: ok")

# A. App state: randTypeTarget
rep(
"  const [globalRandomizationEnabled, setGlobalRandomizationEnabled] = useState(false);",
"  const [globalRandomizationEnabled, setGlobalRandomizationEnabled] = useState(false);\n  const [randTypeTarget, setRandTypeTarget] = useState<string | null>(null);",
"state randTypeTarget")

# B. toggleRandomization принимает randType и шлёт ?rand_type=
rep(
"""  const toggleRandomization = (clientID: string, currentlyEnabled: boolean) =>
    runAction(async () => {
      const endpoint = currentlyEnabled ? "disable" : "enable";
      await request(`/api/clients/${clientID}/randomization/${endpoint}`, { method: "POST" });
      await loadState();
    }, currentlyEnabled ? "Randomization disabled" : "Randomization enabled");""",
"""  const toggleRandomization = (clientID: string, currentlyEnabled: boolean, randType?: number) =>
    runAction(async () => {
      const endpoint = currentlyEnabled ? "disable" : "enable";
      const qs = !currentlyEnabled && randType ? `?rand_type=${randType}` : "";
      await request(`/api/clients/${clientID}/randomization/${endpoint}${qs}`, { method: "POST" });
      await loadState();
    }, currentlyEnabled ? "Randomization disabled" : "Randomization enabled");""",
"toggleRandomization signature")

# C1. Кнопка 🎲: включение → открыть модалку выбора типа; выключение → сразу disable
rep(
"onClick={() => toggleRandomization(client.client_id, client.randomization?.enabled ?? false)}",
"onClick={() => { if (client.randomization?.enabled) { void toggleRandomization(client.client_id, true); } else { setRandTypeTarget(client.client_id); } }}",
"gamble button onClick")

# C2. Метка кнопки 🎲 показывает тип
rep(
'🎲 {client.randomization?.enabled || globalRandomizationEnabled ? "ON" : "OFF"}',
'🎲 {globalRandomizationEnabled ? "ON" : client.randomization?.enabled ? `ON · Т${client.randomization?.rand_type || 1}` : "OFF"}',
"gamble button label")

# D1. Компонент RandTypeModal (перед function App())
modal = '''function RandTypeModal({ clientId, onChoose, onClose }: { clientId: string; onChoose: (ty: number) => void; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-lg border border-border bg-card p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-1 flex items-center justify-between">
          <div className="truncate text-sm font-semibold text-foreground">🎲 Тип рандомизации — {clientId}</div>
          <button type="button" className="rounded px-2 text-muted-foreground hover:bg-muted" onClick={onClose}>✕</button>
        </div>
        <p className="mb-3 text-[11px] text-muted-foreground">Выберите тип. Если закрыть без выбора — рандомизация НЕ включится.</p>
        <div className="grid gap-2">
          <button type="button" className="grid gap-1 rounded-md border border-emerald-500/40 bg-emerald-500/5 p-3 text-left transition-colors hover:bg-emerald-500/10" onClick={() => onChoose(1)}>
            <div className="text-sm font-medium text-emerald-500">Тип 1 — статичный хэш</div>
            <div className="text-[11px] text-muted-foreground">Постоянный случайный хэш вместо client_id. Работает БЕЗ контроля доступа. Ссылка не меняется.</div>
          </button>
          <button type="button" className="grid gap-1 rounded-md border border-sky-500/40 bg-sky-500/5 p-3 text-left transition-colors hover:bg-sky-500/10" onClick={() => onChoose(2)}>
            <div className="text-sm font-medium text-sky-400">Тип 2 — посекундная ротация</div>
            <div className="text-[11px] text-muted-foreground">Хэш меняется каждую секунду (HMAC). Оригинальный client_id работает только для разрешённых устройств через контроль доступа. <span className="text-amber-500">Без настроенного контроля доступа пользоваться нереально — ссылка меняется каждую секунду.</span></div>
          </button>
        </div>
      </div>
    </div>
  );
}

function App() {'''
rep("function App() {", modal, "RandTypeModal component")

# D2. Рендер модалки в App (после ClientAccessModal)
rep(
"      {accessClient && !globalAccessEnabled && <ClientAccessModal clientId={accessClient} onClose={() => setAccessClient(null)} />}",
"      {accessClient && !globalAccessEnabled && <ClientAccessModal clientId={accessClient} onClose={() => setAccessClient(null)} />}\n      {randTypeTarget && (\n        <RandTypeModal\n          clientId={randTypeTarget}\n          onClose={() => setRandTypeTarget(null)}\n          onChoose={(ty) => { const cid = randTypeTarget; setRandTypeTarget(null); void toggleRandomization(cid, false, ty); }}\n        />\n      )}",
"RandTypeModal render")

# E1. Глобальная панель: состояние gType + загрузка + сеттер
rep(
"""  const enabled = globalEnabled ?? false;
  const loading = false;
  const [msg, setMsg] = useState("");""",
"""  const enabled = globalEnabled ?? false;
  const loading = false;
  const [msg, setMsg] = useState("");
  const [gType, setGType] = useState(1);
  useEffect(() => {
    void fetch("/api/settings/randomization/global", { cache: "no-store" })
      .then((r) => r.json())
      .then((b: any) => { if (b && b.rand_type) setGType(b.rand_type); })
      .catch(() => {});
  }, []);
  const setType = async (ty: number) => {
    setGType(ty);
    await fetch("/api/settings/randomization/global", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: true, rand_type: ty }),
    });
    setMsg("Тип сохранён");
  };""",
"global gType state")

# E2. Глобальные радио выбора типа + подсветка (перед {msg && ...})
rep(
"""      {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
      {onClose && (""",
"""      {enabled && (
        <div className="grid gap-1 rounded-md border border-amber-500/40 bg-amber-500/10 p-2">
          <div className="text-[11px] font-medium text-amber-600">Тип рандомизации (глобально)</div>
          <label className="flex items-center gap-1 text-xs cursor-pointer"><input type="radio" name="olc-grand-type" checked={gType === 1} onChange={() => void setType(1)} /> Тип 1 — статичный хэш</label>
          <label className="flex items-center gap-1 text-xs cursor-pointer"><input type="radio" name="olc-grand-type" checked={gType === 2} onChange={() => void setType(2)} /> Тип 2 — посекундная ротация <span className="text-amber-500">(нужен контроль доступа)</span></label>
        </div>
      )}
      {msg && <p className="text-xs text-muted-foreground">{msg}</p>}
      {onClose && (""",
"global type radios")

# F. Выборочная панель: показать тип на строке
rep(
"""                {enabled && randomizedID && (
                  <div className="text-xs text-muted-foreground truncate">
                    Hash: {randomizedID}
                  </div>
                )}""",
"""                {enabled && (
                  <div className="text-xs text-muted-foreground truncate">
                    Тип: {globalEnabled ? "глобальный" : `Т${c.randomization?.rand_type || 1}`}{randomizedID ? ` · Hash: ${randomizedID}` : ""}
                  </div>
                )}""",
"selective row type")

if changed:
    f.write_text(t)
print("[patch-randomization-type-ui] done")
PY
