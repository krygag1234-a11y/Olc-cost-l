#!/usr/bin/env bash
# Olc-cost-l frontend: (1) ГЛОБАЛЬНЫЙ randOn теперь = глоб. рандомизация ИЛИ ЛЮБАЯ
# выборочная (fetch /api/clients/) — чтобы «+» и предупреждение появлялись в
# 🔐 Глобальном контроле доступа даже когда рандомизация только выборочная.
# (2) Кнопка «+» (keyrand) в 🔌 «Доступ к подключению» — ГЛОБАЛЬНО и ВЫБОРОЧНО.
# 🔌 использует bool enforce_connections/conn_enforce; «+» шлёт conn_mode="keyrand"
# + enforce_connections/conn_enforce=false → bool-энфорс остаётся выкл (ИНЕРТНО),
# conn_mode фиксирует keyrand для будущего core-энфорса. При «+» список разрешённых
# для подключения разблокируется с жёлтой обводкой.
# Idempotent. Target: manager src/main.tsx. Run ПОСЛЕ panel-keyrand-off-warning.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-keyrand-plus-conn] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-keyrand-plus-conn] {label}: already applied")
        return
    n = t.count(old)
    if n == 0:
        print(f"[patch-keyrand-plus-conn] WARN {label}: anchor not found")
        return
    if n > 1:
        print(f"[patch-keyrand-plus-conn] WARN {label}: anchor not unique ({n})")
        return
    t = t.replace(old, new, 1)
    changed = True
    print(f"[patch-keyrand-plus-conn] {label}: ok")

TIP = 'У разрешённых полный доступ, у неизвестных — только по рандомизированным путям (разрешённые могут заходить по оригинальным ключам/client_id. Заблокированные также заблокированы).'
W_CONN_T1 = 'При выключении контроля доступа (переключении на «Пускать всех») и включённой рандомизации 1 типа инстансы в подписке станут недоступны по оригинальным ключам шифрования для всех. Не рекомендуем данное действие.'
W_CONN_T2 = 'При выключении контроля доступа (переключении на «Пускать всех») инстансы в подписке станут недоступны для всех. Не рекомендуем данное действие.'

# ============================ ГЛОБАЛЬНО (AccessControlSection) ============================

# 1. connKeyrand state (global)
repl(
    'localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);',
    'localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);\n  const [connKeyrand, setConnKeyrand] = useState(false);',
    "G connKeyrand state",
    guard='return ""; } });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);\n  const [connKeyrand, setConnKeyrand] = useState(false);',
)

# 2. loadRand: включить любую выборочную рандомизацию
repl(
    'const loadRand = async () => { try { const r = await fetch("/api/settings/randomization/global", { cache: "no-store" }); const b = await r.json(); setRandOn(!!b.enabled); setRandType(b.rand_type === 2 ? 2 : 1); } catch { /* ignore */ } };',
    '''const loadRand = async () => {
    try {
      const r = await fetch("/api/settings/randomization/global", { cache: "no-store" });
      const b = await r.json();
      let on = !!b.enabled; let ty = b.rand_type === 2 ? 2 : 1;
      if (!on) {
        try {
          const cr = await fetch("/api/clients/", { cache: "no-store" });
          const cb = await cr.json();
          const cls = Array.isArray(cb.clients) ? cb.clients : [];
          if (cls.some((c: any) => c.randomization?.enabled)) { on = true; ty = cls.some((c: any) => c.randomization?.enabled && c.randomization?.rand_type === 2) ? 2 : 1; }
        } catch { /* ignore */ }
      }
      setRandOn(on); setRandType(ty);
    } catch { /* ignore */ }
  };''',
    "G loadRand any-selective",
    guard="if (cls.some((c: any) => c.randomization?.enabled)) { on = true;",
)

# 3. load connKeyrand (loadSettings)
repl(
    'setEnforceConns(!!sb.enforce_connections);',
    'setEnforceConns(!!sb.enforce_connections); setConnKeyrand(sb.conn_mode === "keyrand");',
    "G load connKeyrand",
    guard='setEnforceConns(!!sb.enforce_connections); setConnKeyrand(sb.conn_mode === "keyrand");',
)

# 4. saveSettings reflect connKeyrand
repl(
    'setEnforceConns(!!b.enforce_connections);',
    'setEnforceConns(!!b.enforce_connections); setConnKeyrand(b.conn_mode === "keyrand");',
    "G save connKeyrand",
    guard='setEnforceConns(!!b.enforce_connections); setConnKeyrand(b.conn_mode === "keyrand");',
)

# 5. saveSettings signature: conn_mode
repl(
    'enforce_connections?: boolean; conn_devices?: any[];',
    'enforce_connections?: boolean; conn_mode?: string; conn_devices?: any[];',
    "G saveSettings sig conn_mode",
    guard='enforce_connections?: boolean; conn_mode?: string; conn_devices?: any[];',
)

# 6. derived connKr (global)
repl(
    '  const connOff = !enforceConns;\n  const dimCls',
    '  const connOff = !enforceConns;\n  const connKr = connKeyrand && randOn;\n  const dimCls',
    "G connKr",
    guard='const connKr = connKeyrand && randOn;\n  const dimCls',
)

# 7. Global 🔌 selector: 3 кнопки
repl(
    '''              <button type="button" disabled={busy}
                className={connOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (connOff) return; const go = () => { setEnforceConns(false); void saveSettings({ enforce_connections: false }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "''' + W_CONN_T2 + '''" : "''' + W_CONN_T1 + '''"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              <button type="button" disabled={busy}
                className={!connOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (!connOff) return; setEnforceConns(true); void saveSettings({ enforce_connections: true }); }}>
                Блокировать неизвестных (+логирование)
              </button>''',
    '''              <button type="button" disabled={busy}
                className={(connOff && !connKr) ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (connOff && !connKr) return; const go = () => { setEnforceConns(false); setConnKeyrand(false); void saveSettings({ enforce_connections: false, conn_mode: "off" }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "''' + W_CONN_T2 + '''" : "''' + W_CONN_T1 + '''"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              {randOn && (
                <button type="button" disabled={busy}
                  title="''' + TIP + '''"
                  className={connKr ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 hover:bg-amber-500/25"}
                  onClick={() => { if (connKr) return; setEnforceConns(false); setConnKeyrand(true); void saveSettings({ enforce_connections: false, conn_mode: "keyrand" }); }}>
                  +
                </button>
              )}
              <button type="button" disabled={busy}
                className={!connOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (!connOff) return; setEnforceConns(true); setConnKeyrand(false); void saveSettings({ enforce_connections: true, conn_mode: "enforce" }); }}>
                Блокировать неизвестных (+логирование)
              </button>''',
    "G 🔌 selector + plus",
    guard='setConnKeyrand(true); void saveSettings({ enforce_connections: false, conn_mode: "keyrand" });',
)

# 8. Global scope region gating
repl(
    '            {!connOff && (\n              <div className="grid gap-2 pl-5">\n                <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">\n                  <label className="flex items-center gap-1">\n                    <input type="radio" name="olc-conn-scope-global"',
    '            {(!connOff || connKr) && (\n              <div className="grid gap-2 pl-5">\n                <div className="flex flex-wrap gap-3 text-[11px] text-muted-foreground">\n                  <label className="flex items-center gap-1">\n                    <input type="radio" name="olc-conn-scope-global"',
    "G scope region gate",
    guard='{(!connOff || connKr) && (\n              <div className="grid gap-2 pl-5">',
)

# 9. Global 🔌 allowed list dim + amber
repl(
    '<div className={"grid gap-2" + dimCls(connOff)} title={connOff ? "Режим «Выключено»: список разрешённых не действует и недоступен — включите «Блокировать неизвестных»" : undefined}>',
    '<div className={"grid gap-2 rounded-md border p-2 transition-colors duration-300 " + (connKr ? "border-amber-500/50 bg-amber-500/5" : "border-sky-500/30 bg-sky-500/5") + dimCls(connOff && !connKr)} title={(connOff && !connKr) ? "Режим «Выключено»: список разрешённых не действует и недоступен — включите «Блокировать неизвестных»" : undefined}>',
    "G 🔌 list amber",
    guard='"grid gap-2 rounded-md border p-2 transition-colors duration-300 " + (connKr ? "border-amber-500/50 bg-amber-500/5" : "border-sky-500/30 bg-sky-500/5") + dimCls(connOff && !connKr)}',
)

# ============================ ВЫБОРОЧНО (ClientAccessModal) ============================

# 10. connKeyrand state (per-client)
repl(
    'conn_ban: [] });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);',
    'conn_ban: [] });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);\n  const [connKeyrand, setConnKeyrand] = useState(false);',
    "C connKeyrand state",
    guard='conn_ban: [] });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);\n  const [connKeyrand, setConnKeyrand] = useState(false);',
)

# 11. load connKeyrand (load + save)
repl(
    'setConnEnforce(!!b.conn_enforce);',
    'setConnEnforce(!!b.conn_enforce); setConnKeyrand(b.conn_mode === "keyrand");',
    "C load connKeyrand",
    guard='setConnEnforce(!!b.conn_enforce); setConnKeyrand(b.conn_mode === "keyrand");',
)
repl(
    'setConnEnforce(!!cc.conn_enforce);',
    'setConnEnforce(!!cc.conn_enforce); setConnKeyrand(cc.conn_mode === "keyrand");',
    "C save connKeyrand",
    guard='setConnEnforce(!!cc.conn_enforce); setConnKeyrand(cc.conn_mode === "keyrand");',
)

# 12. save signature conn_mode (per-client)
repl(
    'conn_enforce?: boolean; conn_scope?: string;',
    'conn_enforce?: boolean; conn_mode?: string; conn_scope?: string;',
    "C save sig conn_mode",
    guard='conn_enforce?: boolean; conn_mode?: string; conn_scope?: string;',
)

# 13. per-client connKr
repl(
    '  const connOff = !connEnforce;',
    '  const connOff = !connEnforce;\n  const connKr = connKeyrand && randOn;',
    "C connKr",
    guard='const connOff = !connEnforce;\n  const connKr = connKeyrand && randOn;',
)

# 14. per-client 🔌 selector: 3 кнопки
repl(
    '''                <button type="button" disabled={busy}
                  className={connOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                  onClick={() => { if (connOff) return; const go = () => { setConnEnforce(false); void save({ conn_enforce: false }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "''' + W_CONN_T2 + '''" : "''' + W_CONN_T1 + '''"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
                  Выключено (пускать всех (кроме бан-листа), лог)
                </button>
                <button type="button" disabled={busy}
                  className={!connOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                  onClick={() => { if (!connOff) return; setConnEnforce(true); void save({ conn_enforce: true }); }}>
                  Блокировать неизвестных (+логирование)
                </button>''',
    '''                <button type="button" disabled={busy}
                  className={(connOff && !connKr) ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                  onClick={() => { if (connOff && !connKr) return; const go = () => { setConnEnforce(false); setConnKeyrand(false); void save({ conn_enforce: false, conn_mode: "off" }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "''' + W_CONN_T2 + '''" : "''' + W_CONN_T1 + '''"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>
                  Выключено (пускать всех (кроме бан-листа), лог)
                </button>
                {randOn && (
                  <button type="button" disabled={busy}
                    title="''' + TIP + '''"
                    className={connKr ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 hover:bg-amber-500/25"}
                    onClick={() => { if (connKr) return; setConnEnforce(false); setConnKeyrand(true); void save({ conn_enforce: false, conn_mode: "keyrand" }); }}>
                    +
                  </button>
                )}
                <button type="button" disabled={busy}
                  className={!connOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                  onClick={() => { if (!connOff) return; setConnEnforce(true); setConnKeyrand(false); void save({ conn_enforce: true, conn_mode: "enforce" }); }}>
                  Блокировать неизвестных (+логирование)
                </button>''',
    "C 🔌 selector + plus",
    guard='setConnKeyrand(true); void save({ conn_enforce: false, conn_mode: "keyrand" });',
)

# 15. per-client 🔌 list dim + amber
repl(
    '<div className={"grid gap-2 rounded-md border border-sky-500/30 bg-sky-500/5 p-2" + dimCls(connOff)}\n                title={connOff ? "Режим «Выключено»: список разрешённых не действует и недоступен — включите «Блокировать неизвестных»" : undefined}>',
    '<div className={"grid gap-2 rounded-md border p-2 transition-colors duration-300 " + (connKr ? "border-amber-500/50 bg-amber-500/5" : "border-sky-500/30 bg-sky-500/5") + dimCls(connOff && !connKr)}\n                title={(connOff && !connKr) ? "Режим «Выключено»: список разрешённых не действует и недоступен — включите «Блокировать неизвестных»" : undefined}>',
    "C 🔌 list amber",
    guard='"grid gap-2 rounded-md border p-2 transition-colors duration-300 " + (connKr ? "border-amber-500/50 bg-amber-500/5" : "border-sky-500/30 bg-sky-500/5")',
)

if changed:
    f.write_text(t)
    print("[patch-keyrand-plus-conn] OK: main.tsx updated")
else:
    print("[patch-keyrand-plus-conn] no changes")
PY
