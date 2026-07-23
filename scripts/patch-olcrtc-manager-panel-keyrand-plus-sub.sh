#!/usr/bin/env bash
# Olc-cost-l frontend: кнопка «+» (третий режим контроля доступа) в 🎫 «Доступ к
# подписке» — ГЛОБАЛЬНО (AccessControlSection) и ВЫБОРОЧНО (ClientAccessModal).
# «+» появляется ТОЛЬКО при включённой рандомизации (единый тип 1/2 — client_id +
# крипто-ключи). Режимы: «Выключено» (monitor/off) | «+» (keyrand) | «Блокировать»
# (enforce). Шлёт mode="keyrand" (backend уже персистит; olcAccessDecision пока
# трактует keyrand как monitor → ИНЕРТНО, без риска для живой bs). При «+» списки
# разрешённых разблокируются с ЖЁЛТОЙ обводкой. Если рандомизация выключена, а режим
# остался «keyrand» — мини-модалка сброса (Выключено/Блокировать; крестик=оставить).
# Idempotent. Target: manager src/main.tsx. Run ПОСЛЕ panel-access-control-ui и
# panel-client-access-ui.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-keyrand-plus-sub] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None, count=1):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-keyrand-plus-sub] {label}: already applied")
        return
    n = t.count(old)
    if n == 0:
        print(f"[patch-keyrand-plus-sub] WARN {label}: anchor not found")
        return
    if count == 1 and n > 1:
        print(f"[patch-keyrand-plus-sub] WARN {label}: anchor not unique ({n})")
        return
    t = t.replace(old, new, count)
    changed = True
    print(f"[patch-keyrand-plus-sub] {label}: ok ({n})")

# ============================ ГЛОБАЛЬНО (AccessControlSection) ============================

# 1. mode type widening
repl(
    'const [mode, setMode] = useState<"monitor" | "enforce">("monitor");',
    'const [mode, setMode] = useState<"monitor" | "enforce" | "keyrand">("monitor");',
    "G mode type",
    guard='"monitor" | "enforce" | "keyrand"',
)

# 2. randOn state
repl(
    '  const [connClearedAt, setConnClearedAt] = useState<string>(() => { try { return localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });',
    '''  const [connClearedAt, setConnClearedAt] = useState<string>(() => { try { return localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });
  const [randOn, setRandOn] = useState(false);''',
    "G randOn state",
    guard="const [randOn, setRandOn] = useState(false);\n\n  const loadSettings",
)

# 3. mode load keyrand-aware
repl(
    'setMode(sb.mode === "enforce" ? "enforce" : "monitor");',
    'setMode(sb.mode === "enforce" ? "enforce" : sb.mode === "keyrand" ? "keyrand" : "monitor");',
    "G mode load",
    guard='sb.mode === "keyrand" ? "keyrand" : "monitor"',
)

# 4. loadAll fetches randomization
repl(
    '  const loadAll = async () => { await loadSettings(); await loadAttempts(); };',
    '''  const loadRand = async () => { try { const r = await fetch("/api/settings/randomization/global", { cache: "no-store" }); const b = await r.json(); setRandOn(!!b.enabled); } catch { /* ignore */ } };
  const loadAll = async () => { await loadSettings(); await loadAttempts(); await loadRand(); };''',
    "G loadRand",
    guard="const loadRand = async () =>",
)

# 5. subOff + subKeyrand (global) — keyrand активен ТОЛЬКО при randOn (иначе
# стейл keyrand отображается как «Выключено», совпадая с backend monitor).
repl(
    '''  const subOff = mode !== "enforce";
  const connOff = !enforceConns;''',
    '''  const subKeyrand = mode === "keyrand" && randOn;
  const subOff = mode !== "enforce" && !subKeyrand;
  const connOff = !enforceConns;''',
    "G subOff/subKeyrand",
    guard="const subKeyrand = mode === \"keyrand\" && randOn;\n  const subOff = mode !== \"enforce\" && !subKeyrand;\n  const connOff = !enforceConns;",
)

# 6. 🎫 selector: enforce highlight -> mode==="enforce" + insert «+» between
repl(
    '''              <button type="button" disabled={busy}
                className={subOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (subOff) return; setMode("monitor"); void saveSettings({ mode: "monitor" }); }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              <button type="button" disabled={busy}
                className={!subOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (!subOff) return; setMode("enforce"); void saveSettings({ mode: "enforce" }); }}>
                Блокировать неизвестных (+логирование)
              </button>''',
    '''              <button type="button" disabled={busy}
                className={subOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (subOff) return; setMode("monitor"); void saveSettings({ mode: "monitor" }); }}>
                Выключено (пускать всех (кроме бан-листа), лог)
              </button>
              {randOn && (
                <button type="button" disabled={busy}
                  title="У разрешённых полный доступ, у неизвестных — только по рандомизированным путям (разрешённые могут заходить по оригинальным ключам/client_id. Заблокированные также заблокированы)."
                  className={subKeyrand ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 hover:bg-amber-500/25"}
                  onClick={() => { if (subKeyrand) return; setMode("keyrand"); void saveSettings({ mode: "keyrand" }); }}>
                  +
                </button>
              )}
              <button type="button" disabled={busy}
                className={mode === "enforce" ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
                onClick={() => { if (mode === "enforce") return; setMode("enforce"); void saveSettings({ mode: "enforce" }); }}>
                Блокировать неизвестных (+логирование)
              </button>''',
    "G 🎫 selector + plus",
    guard='setMode("keyrand"); void saveSettings({ mode: "keyrand" }); }}>\n                  +',
)

# 7. Allowed-devices container border amber when keyrand (global)
repl(
    '''          <div className={"grid gap-2 rounded-md border border-emerald-600/30 bg-emerald-500/5 p-3" + dimCls(subOff)}
            title={subOff ? "Режим «Выключено»: списки разрешённых не действуют и недоступны — включите «Блокировать неизвестных»" : undefined}>
            <div className="text-xs font-semibold text-emerald-400">✅ Разрешённые устройства (получение подписки){subOff ? " — не действуют в режиме «Выключено»" : ""}</div>''',
    '''          <div className={"grid gap-2 rounded-md border p-3" + (subKeyrand ? " border-amber-500/50 bg-amber-500/5" : " border-emerald-600/30 bg-emerald-500/5") + dimCls(subOff)}
            title={subOff ? "Режим «Выключено»: списки разрешённых не действуют и недоступны — включите «Блокировать неизвестных»" : undefined}>
            <div className={"text-xs font-semibold " + (subKeyrand ? "text-amber-400" : "text-emerald-400")}>✅ Разрешённые устройства (получение подписки){subKeyrand ? " (режим «+»: у них полный доступ)" : subOff ? " — не действуют в режиме «Выключено»" : ""}</div>''',
    "G allowed border amber",
    guard='(режим «+»: у них полный доступ)',
)

# ============================ ВЫБОРОЧНО (ClientAccessModal) ============================

# 8. per-client randOn state (после glob state)
repl(
    "  const [glob, setGlob] = useState<any>({ devices: [], ban: [], allow_ips: [], ban_ips: [], conn_devices: [], conn_ban: [] });",
    '''  const [glob, setGlob] = useState<any>({ devices: [], ban: [], allow_ips: [], ban_ips: [], conn_devices: [], conn_ban: [] });
  const [randOn, setRandOn] = useState(false);''',
    "C randOn state",
    guard="conn_ban: [] });\n  const [randOn, setRandOn] = useState(false);",
)

# 9. per-client mode load keyrand-aware
repl(
    'setMode(b.mode === "enforce" ? "enforce" : "off"); // off+monitor слиты в «Выключено»',
    'setMode(b.mode === "enforce" ? "enforce" : b.mode === "keyrand" ? "keyrand" : "off"); // off+monitor слиты в «Выключено»',
    "C mode load",
    guard='b.mode === "keyrand" ? "keyrand" : "off"',
)

# 9b. per-client randOn fetch (глоб. рандомизация ИЛИ рандомизация этого клиента)
repl(
    '''      const cl = (stb.clients || []).find((c: any) => String(c.client_id) === clientId);
      setInstances((cl?.locations || []).map((l: any) => ({ room_id: String(l.room_id || ""), name: String(l.name || l.room_id || "") })));''',
    '''      const cl = (stb.clients || []).find((c: any) => String(c.client_id) === clientId);
      setInstances((cl?.locations || []).map((l: any) => ({ room_id: String(l.room_id || ""), name: String(l.name || l.room_id || "") })));
      try { const gr = await fetch("/api/settings/randomization/global", { cache: "no-store" }); const gb = await gr.json(); setRandOn(!!gb.enabled || !!(cl?.randomization?.enabled)); } catch { setRandOn(!!(cl?.randomization?.enabled)); }''',
    "C randOn fetch",
    guard="setRandOn(!!gb.enabled || !!(cl?.randomization?.enabled));",
)

# 10. per-client subOff + subKeyrand
repl(
    '''  const subOff = mode !== "enforce";
  const connOff = !connEnforce;''',
    '''  const subKeyrand = mode === "keyrand" && randOn;
  const subOff = mode !== "enforce" && !subKeyrand;
  const connOff = !connEnforce;''',
    "C subOff/subKeyrand",
    guard='const subKeyrand = mode === "keyrand" && randOn;\n  const subOff = mode !== "enforce" && !subKeyrand;\n  const connOff = !connEnforce;',
)

# 11. per-client 🎫 selector + «+»
repl(
    '''              className={subOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
              onClick={() => { if (subOff) return; setMode("off"); void save({ mode: "off" }); }}>
              Выключено (пускать всех (кроме бан-листа), лог)
            </button>
            <button type="button" disabled={busy}
              className={!subOff ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
              onClick={() => { if (!subOff) return; setMode("enforce"); void save({ mode: "enforce" }); }}>
              Блокировать неизвестных (+логирование)
            </button>''',
    '''              className={subOff ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
              onClick={() => { if (subOff) return; setMode("off"); void save({ mode: "off" }); }}>
              Выключено (пускать всех (кроме бан-листа), лог)
            </button>
            {randOn && (
              <button type="button" disabled={busy}
                title="У разрешённых полный доступ, у неизвестных — только по рандомизированным путям (разрешённые могут заходить по оригинальным ключам/client_id. Заблокированные также заблокированы)."
                className={subKeyrand ? "rounded-md border border-emerald-600/60 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300" : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 hover:bg-amber-500/25"}
                onClick={() => { if (subKeyrand) return; setMode("keyrand"); void save({ mode: "keyrand" }); }}>
                +
              </button>
            )}
            <button type="button" disabled={busy}
              className={mode === "enforce" ? "rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300" : "rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"}
              onClick={() => { if (mode === "enforce") return; setMode("enforce"); void save({ mode: "enforce" }); }}>
              Блокировать неизвестных (+логирование)
            </button>''',
    "C 🎫 selector + plus",
    guard='setMode("keyrand"); void save({ mode: "keyrand" }); }}>\n                +',
)

# 12. per-client allowed container border amber
repl(
    '''          <div className={"grid gap-2 rounded-md border border-emerald-600/30 bg-emerald-500/5 p-2" + dimCls(subOff)}
            title={subOff ? "Режим «Выключено»: списки разрешённых не действуют и недоступны — включите «Блокировать неизвестных»" : undefined}>
            <div className="text-xs font-semibold text-emerald-400">✅ Разрешённые устройства{subOff ? " — не действуют в режиме «Выключено»" : ""}</div>''',
    '''          <div className={"grid gap-2 rounded-md border p-2" + (subKeyrand ? " border-amber-500/50 bg-amber-500/5" : " border-emerald-600/30 bg-emerald-500/5") + dimCls(subOff)}
            title={subOff ? "Режим «Выключено»: списки разрешённых не действуют и недоступны — включите «Блокировать неизвестных»" : undefined}>
            <div className={"text-xs font-semibold " + (subKeyrand ? "text-amber-400" : "text-emerald-400")}>✅ Разрешённые устройства{subKeyrand ? " (режим «+»: полный доступ)" : subOff ? " — не действуют в режиме «Выключено»" : ""}</div>''',
    "C allowed border amber",
    guard='(режим «+»: полный доступ)',
)

if changed:
    f.write_text(t)
    print("[patch-keyrand-plus-sub] OK: main.tsx updated")
else:
    print("[patch-keyrand-plus-sub] no changes")
PY
