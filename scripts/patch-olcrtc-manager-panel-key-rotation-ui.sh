#!/usr/bin/env bash
# Olc-cost-l frontend: секция «♻️ Автосмена ключей» (Z5-B) — ОТДЕЛЬНАЯ секция
# рядом с рандомизациями (не внутри). Глобальный тумблер + per-client тумблеры
# (цветные кнопки). Работает с /api/settings/key-rotation и
# /api/clients/:id/key-rotation. Idempotent. Target: manager src/main.tsx.
# Run ПОСЛЕ selective-randomization-ui (нужен анкор <MainSettingsAutodetectLink).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-key-rotation-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Компонент KeyRotationSection (перед function App) ---
comp_anchor = 'function App()'
comp_block = r'''// ============================================================================
// Olc-cost-l: «♻️ Автосмена ключей» (Z5-B). ОТДЕЛЬНАЯ секция рядом с
// рандомизациями. Раз в интервал автообновления подписки (N ч) сервер
// перегенерирует ОРИГИНАЛЬНЫЕ ключи шифрования инстансов; занятые (с активным
// туннелем) откладываются до следующего круга. Клиент подхватывает новые ключи
// при автообновлении. Независимо от рандомизации. См. docs/ACCESS-CONTROL.md.
// ============================================================================
function KeyRotationSection() {
  const [globalEnabled, setGlobalEnabled] = useState(false);
  const [clients, setClients] = useState<string[]>([]);
  const [perClient, setPerClient] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const load = async () => {
    try {
      const r = await fetch("/api/settings/key-rotation", { cache: "no-store" });
      const b = await r.json();
      setGlobalEnabled(!!b.global_enabled);
      setPerClient((b.clients && typeof b.clients === "object") ? b.clients : {});
    } catch { /* ignore */ }
    try {
      const r = await fetch("/api/clients/", { cache: "no-store" });
      const b = await r.json();
      setClients((Array.isArray(b.clients) ? b.clients : []).map((c: any) => String(c.client_id)));
    } catch { /* ignore */ }
  };
  useEffect(() => { void load(); }, []);

  const saveGlobal = async (v: boolean) => {
    setBusy(true); setMsg(null);
    try {
      const r = await fetch("/api/settings/key-rotation", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ global_enabled: v }) });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
      setGlobalEnabled(!!b.global_enabled);
      setPerClient((b.clients && typeof b.clients === "object") ? b.clients : {});
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };
  const saveClient = async (id: string, v: boolean) => {
    setBusy(true); setMsg(null);
    try {
      const r = await fetch(`/api/clients/${encodeURIComponent(id)}/key-rotation`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ enabled: v }) });
      const b = await r.json();
      if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
      setPerClient((b.clients && typeof b.clients === "object") ? b.clients : {});
    } catch (e: any) { setMsg("Ошибка: " + (e?.message || String(e))); } finally { setBusy(false); }
  };

  return (
    <section className="grid gap-3 rounded-md border border-amber-500/30 bg-amber-500/5 p-4">
      <div>
        <div className="text-sm font-semibold text-amber-400">♻️ Автосмена ключей</div>
        <div className="mt-1 grid gap-1 text-xs text-muted-foreground">
          <div>Раз в <b className="text-foreground">N ч</b> сервер перегенерирует <b className="text-foreground">оригинальные ключи шифрования</b> инстансов. Клиент подхватывает новые ключи при автообновлении подписки. Защита от <b className="text-foreground">утёкшей подписки</b> (слитый ключ протухает за N). Работает независимо от рандомизации ключей/ID.</div>
          <div><b className="text-foreground">N = интервал автообновления подписки</b> (заголовок <span className="font-mono">profile-update-interval</span>, который вы задаёте пикером часов): для <b className="text-foreground">глобальной</b> смены берётся интервал из <b className="text-foreground">общих настроек подписки</b>; для <b className="text-foreground">выборочной</b> (по клиенту) — интервал, заданный у этого клиента в <span className="font-mono">Edit</span>. Если интервал нигде не задан — по умолчанию <b className="text-foreground">24 ч</b>.</div>
          <div>Инстансы с <b className="text-foreground">активным туннелем пропускаются</b> до следующего круга — их ключ не меняется, пока идёт сессия (живые подключения не рвём).</div>
        </div>
      </div>

      {/* Глобальный режим */}
      <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
        <div className="text-xs font-semibold text-foreground">🌐 Глобально (все клиенты и инстансы)</div>
        <div className="flex flex-wrap gap-2 text-xs">
          <button type="button" disabled={busy}
            className={!globalEnabled ? "rounded-md border border-border px-2 py-1 font-medium text-muted-foreground hover:bg-muted" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
            onClick={() => { if (!globalEnabled) return; void saveGlobal(false); }}>
            Выключено
          </button>
          <button type="button" disabled={busy}
            className={globalEnabled ? "rounded-md border border-amber-500/60 bg-amber-500/15 px-2 py-1 font-medium text-amber-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
            onClick={() => { if (globalEnabled) return; void saveGlobal(true); }}>
            ♻️ Включить для всех
          </button>
        </div>
        {globalEnabled && <div className="text-[10px] leading-snug text-amber-500/90">Включено глобально: ключи всех инстансов всех подписок ротируются каждый их интервал автообновления. Индивидуальные тумблеры ниже не требуются.</div>}
      </div>

      {/* Выборочно по клиентам */}
      <div className={"grid gap-2 rounded-md border border-border bg-card/40 p-3" + (globalEnabled ? " pointer-events-none opacity-40 select-none" : "")}
        title={globalEnabled ? "Включено глобально — индивидуальный выбор не нужен" : undefined}>
        <div className="text-xs font-semibold text-foreground">🎯 Выборочно (отдельные подписки)</div>
        {clients.length === 0 && <div className="text-[11px] text-muted-foreground">Клиентов нет.</div>}
        <div className="grid gap-1">
          {clients.map((id) => {
            const on = globalEnabled || !!perClient[id];
            return (
              <div key={id} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1 text-[11px]">
                <span className="min-w-0 flex-1 truncate font-mono">{id}</span>
                <button type="button" disabled={busy || globalEnabled}
                  className={on ? "shrink-0 rounded border border-amber-500/60 bg-amber-500/15 px-2 py-1 font-medium text-amber-300" : "shrink-0 rounded border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                  onClick={() => void saveClient(id, !perClient[id])}>
                  {on ? "♻️ Вкл" : "Выкл"}
                </button>
              </div>
            );
          })}
        </div>
        <div className="text-[10px] leading-snug text-muted-foreground">Ротируются все инстансы выбранной подписки (кроме занятых — до следующего круга). Интервал N = автообновление подписки этого клиента (Edit); если у клиента не задано — глобальный интервал; если и он не задан — 24 ч.</div>
      </div>

      {msg && <div className="text-xs text-red-500 whitespace-pre-wrap">{msg}</div>}
    </section>
  );
}

'''
if 'function KeyRotationSection()' in t:
    print("[patch-key-rotation-ui] component already present")
elif comp_anchor in t:
    t = t.replace(comp_anchor, comp_block + comp_anchor, 1); changed = True
    print("[patch-key-rotation-ui] added KeyRotationSection component")
else:
    print("[patch-key-rotation-ui] WARN: function App anchor not found")

# --- 2. Рендер секции рядом с рандомизациями (перед <MainSettingsAutodetectLink) ---
render_anchor = '<MainSettingsAutodetectLink'
render_add = '''<div className="py-2"><KeyRotationSection /></div>
            <MainSettingsAutodetectLink'''
if '<KeyRotationSection />' in t:
    print("[patch-key-rotation-ui] render already present")
elif render_anchor in t:
    t = t.replace(render_anchor, render_add, 1); changed = True
    print("[patch-key-rotation-ui] rendered <KeyRotationSection /> before MainSettingsAutodetectLink")
else:
    print("[patch-key-rotation-ui] WARN: MainSettingsAutodetectLink anchor not found")

if changed:
    f.write_text(t)
    print("[patch-key-rotation-ui] OK: main.tsx updated")
else:
    print("[patch-key-rotation-ui] no changes (idempotent)")
PY
