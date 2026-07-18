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
modal = '''function Type2Warning({ show }: { show: boolean }) {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    if (!show) { setVisible(false); return; }
    const id = window.setTimeout(() => setVisible(true), 1200);
    return () => window.clearTimeout(id);
  }, [show]);
  if (!visible) return null;
  return (
    <span className="mt-1 block text-[10px] leading-tight text-amber-500">
      ⚠️ Тип 2 без контроля доступа: ссылка меняется каждую секунду — пользоваться нереально. Настройте контроль доступа (⚙), тогда оригинальный client_id заработает для разрешённых устройств.
    </span>
  );
}

function RandTypeModal({ clientId, onChoose, onClose, edit }: { clientId: string; onChoose: (ty: number) => void; onClose: () => void; edit?: boolean }) {
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-lg border border-border bg-card p-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-1 flex items-center justify-between">
          <div className="truncate text-sm font-semibold text-foreground">🎲 {edit ? "Изменить тип" : "Тип рандомизации"} — {clientId}</div>
          <button type="button" className="rounded px-2 text-muted-foreground hover:bg-muted" onClick={onClose}>✕</button>
        </div>
        <p className="mb-3 text-[11px] text-muted-foreground">{edit ? "Выберите новый тип. Сгенерированный хэш сохранится. Закрыть без выбора — оставить как есть." : "Выберите тип. Если закрыть без выбора — рандомизация НЕ включится."}</p>
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

# G. Выборочная панель: toggle-функция → applyRand + стейт модалки типа
rep(
"""  const toggleRandomization = async (clientID: string, currentEnabled: boolean) => {
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
  };""",
"""  const [typeTarget, setTypeTarget] = useState<{ id: string; edit: boolean } | null>(null);
  const applyRand = async (clientID: string, enabled: boolean, randType?: number) => {
    const body: any = { enabled };
    if (enabled && randType) body.rand_type = randType;
    const res = await fetch(`/api/clients/${encodeURIComponent(clientID)}/randomization`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (res.ok) {
      setMsg(`Рандомизация ${enabled ? "включена" : "отключена"} для ${clientID}`);
      loadClients();
    } else {
      setMsg(`Ошибка: HTTP ${res.status}`);
    }
  };""",
"selective applyRand + typeTarget")

# H. Выборочная панель: чекбокс → мини-модалка (вкл), карандашик (edit)
rep(
'''                <div className="flex items-center justify-between">
                  <div className="text-xs font-medium truncate flex-1">{c.client_id}</div>
                  <label className="flex items-center gap-1">
                    <input
                      type="checkbox"
                      checked={enabled}
                      disabled={globalEnabled}
                      onChange={() => toggleRandomization(c.client_id, perClientEnabled)}
                      className={globalEnabled ? "rounded opacity-50 cursor-not-allowed" : "rounded"}
                    />
                    <span className="text-xs">{globalEnabled ? "ON (глобально)" : enabled ? "On" : "Off"}</span>
                  </label>
                </div>''',
'''                <div className="flex items-center justify-between gap-2">
                  <div className="text-xs font-medium truncate flex-1">{c.client_id}</div>
                  {perClientEnabled && !globalEnabled && (
                    <button type="button" className="rounded border border-border px-1 text-xs text-muted-foreground hover:bg-muted" title="Изменить тип рандомизации" onClick={() => setTypeTarget({ id: c.client_id, edit: true })}>✏️</button>
                  )}
                  <label className="flex items-center gap-1">
                    <input
                      type="checkbox"
                      checked={enabled}
                      disabled={globalEnabled}
                      onChange={() => { if (perClientEnabled) { void applyRand(c.client_id, false); } else { setTypeTarget({ id: c.client_id, edit: false }); } }}
                      className={globalEnabled ? "rounded opacity-50 cursor-not-allowed" : "rounded"}
                    />
                    <span className="text-xs">{globalEnabled ? "ON (глобально)" : enabled ? "On" : "Off"}</span>
                  </label>
                </div>''',
"selective checkbox+pencil")

# I. Выборочная панель: рендер RandTypeModal
rep(
'      {msg && <p className="text-xs text-amber-600">{msg}</p>}',
'''      {typeTarget && (
        <RandTypeModal
          clientId={typeTarget.id}
          edit={typeTarget.edit}
          onClose={() => setTypeTarget(null)}
          onChoose={(ty) => { const tt = typeTarget; setTypeTarget(null); void applyRand(tt.id, true, ty); }}
        />
      )}
      {msg && <p className="text-xs text-amber-600">{msg}</p>}''',
"selective modal render")

# ── Этап 3: UI типа 2 ──
# J1. App: состояние accessCfg (per-client контроль доступа настроен?)
rep(
"  const [globalAccessEnabled, setGlobalAccessEnabled] = useState(false);",
"  const [globalAccessEnabled, setGlobalAccessEnabled] = useState(false);\n  const [accessCfg, setAccessCfg] = useState<Record<string, boolean>>({});\n  const [accessLoaded, setAccessLoaded] = useState(false);",
"accessCfg state")

# J2. App: загрузка per-client access-конфига вместе с globalAccessEnabled
rep(
'    const load = async () => { try { const r = await fetch("/api/access/settings", { cache: "no-store" }); const b = await r.json(); if (!stop) setGlobalAccessEnabled(!!b.enabled); } catch { /* ignore */ } };',
'    const load = async () => { try { const r = await fetch("/api/access/settings", { cache: "no-store" }); const b = await r.json(); if (!stop) { setGlobalAccessEnabled(!!b.enabled); const m: Record<string, boolean> = {}; const cl = b.clients || {}; Object.keys(cl).forEach((k) => { const c = cl[k] || {}; m[k] = !!((c.mode && c.mode !== "off") || (Array.isArray(c.allow) && c.allow.length) || (Array.isArray(c.allow_ips) && c.allow_ips.length) || c.conn_enforce); }); setAccessCfg(m); setAccessLoaded(true); } } catch { /* ignore */ } };',
"accessCfg load")

# K. Карточка клиента: метка типа (тип2 → ротация) + предупреждение при типе2 без контроля доступа
rep(
'''                        {globalRandomizationEnabled && client.randomization?.randomized_id && (
                          <span className="mt-1 block truncate text-xs text-muted-foreground">
                            🔒 {client.randomization.randomized_id}
                          </span>
                        )}''',
'''                        {client.randomization?.enabled ? (
                          <span className="mt-1 block truncate text-xs text-muted-foreground">
                            {client.randomization?.rand_type === 2
                              ? "🔄 ротация каждую секунду"
                              : (client.randomization?.randomized_id ? `🔒 ${client.randomization.randomized_id}` : "🔒 рандомизированный хэш")}
                          </span>
                        ) : globalRandomizationEnabled && client.randomization?.randomized_id ? (
                          <span className="mt-1 block truncate text-xs text-muted-foreground">
                            🔒 {client.randomization.randomized_id}
                          </span>
                        ) : null}
                        <Type2Warning show={!!(client.randomization?.enabled && client.randomization?.rand_type === 2 && accessLoaded && !globalAccessEnabled && !accessCfg[client.client_id])} />''',
"card type-2 label + warning")

# L. Edit: оптимистично мигрировать accessCfg на новый client_id (без мигающего предупреждения)
rep(
'''        }),
      });
      setEditClient(null);
    }, "Клиент обновлен");''',
'''        }),
      });
      const _oldId = editClient.client_id;
      const _newId = editForm.client_id.trim();
      if (_newId !== _oldId) {
        setAccessCfg((prev) => { if (prev[_oldId] === undefined) return prev; const m = { ...prev }; m[_newId] = m[_oldId]; delete m[_oldId]; return m; });
      }
      setEditClient(null);
    }, "Клиент обновлен");''',
"edit accessCfg migration")

if changed:
    f.write_text(t)
print("[patch-randomization-type-ui] done")
PY