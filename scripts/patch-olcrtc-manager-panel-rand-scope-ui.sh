#!/usr/bin/env bash
# Olc-cost-l frontend: СКОУП рандомизации — селектор «Область действия» в секции
# «Доп. функции рандомизации» (both|client_id|crypto, дефолт both) + гейт «+» и
# предупреждений по скоупу: client_id → показываются в 🎫, ключи → в 🔌.
# randSub = randOn && scope!=crypto (🎫); randConn = randOn && scope!=client_id (🔌).
# Idempotent. Target: manager src/main.tsx. Run ПОСЛЕ access-polish (последним из
# keyrand-серии).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-rand-scope-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
orig = t

# 1. randScope state в обоих access-компонентах (replace_all по randType-строке)
old = '  const [randType, setRandType] = useState(1);'
new = '  const [randType, setRandType] = useState(1);\n  const [randScope, setRandScope] = useState("both");'
if 'const [randScope, setRandScope] = useState("both");' not in t:
    n = t.count(old)
    t = t.replace(old, new)
    print(f"[patch-rand-scope-ui] randScope state: ok ({n})")
else:
    print("[patch-rand-scope-ui] randScope state: already applied")

# 2. randSub/randConn defs + subKeyrand scope-aware (replace_all, оба компонента)
old = '  const subKeyrand = mode === "keyrand" && randOn;'
new = '  const randSub = randOn && randScope !== "crypto";\n  const randConn = randOn && randScope !== "client_id";\n  const subKeyrand = mode === "keyrand" && randSub;'
if 'const randSub = randOn && randScope !== "crypto";' not in t:
    n = t.count(old)
    t = t.replace(old, new)
    print(f"[patch-rand-scope-ui] randSub/randConn + subKeyrand: ok ({n})")
else:
    print("[patch-rand-scope-ui] randSub/randConn: already applied")

# 3. connKr scope-aware (replace_all)
old = '  const connKr = connKeyrand && randOn;'
new = '  const connKr = connKeyrand && randConn;'
if old in t:
    n = t.count(old)
    t = t.replace(old, new)
    print(f"[patch-rand-scope-ui] connKr scope: ok ({n})")
else:
    print("[patch-rand-scope-ui] connKr scope: already applied/nf")

# 4. fetch randScope — global loadRand
old = '      setRandOn(on); setRandType(ty);'
new = '      setRandOn(on); setRandType(ty); setRandScope((b.rand_scope === "client_id" || b.rand_scope === "crypto") ? b.rand_scope : "both");'
if 'setRandScope((b.rand_scope' not in t:
    if old in t:
        t = t.replace(old, new, 1)
        print("[patch-rand-scope-ui] G fetch randScope: ok")
    else:
        print("[patch-rand-scope-ui] WARN G fetch randScope: anchor nf")
else:
    print("[patch-rand-scope-ui] G fetch randScope: already applied")

# 5. fetch randScope — per-client
old = 'setRandType(gb.enabled ? (gb.rand_type === 2 ? 2 : 1) : ((cl?.randomization?.rand_type) === 2 ? 2 : 1)); } catch'
new = 'setRandType(gb.enabled ? (gb.rand_type === 2 ? 2 : 1) : ((cl?.randomization?.rand_type) === 2 ? 2 : 1)); setRandScope((gb.rand_scope === "client_id" || gb.rand_scope === "crypto") ? gb.rand_scope : "both"); } catch'
if 'setRandScope((gb.rand_scope' not in t:
    if old in t:
        t = t.replace(old, new, 1)
        print("[patch-rand-scope-ui] C fetch randScope: ok")
    else:
        print("[patch-rand-scope-ui] WARN C fetch randScope: anchor nf")
else:
    print("[patch-rand-scope-ui] C fetch randScope: already applied")

# 6. Гейт «+»-кнопок: {randOn && ( → последовательно [randSub, randConn, randSub, randConn]
if '{randSub && (' not in t and '{randConn && (' not in t:
    seq = ["randSub", "randConn", "randSub", "randConn"]
    okc = 0
    for fv in seq:
        if "{randOn && (" in t:
            t = t.replace("{randOn && (", "{" + fv + " && (", 1)
            okc += 1
    print(f"[patch-rand-scope-ui] «+» visibility gate: ok ({okc}/4)")
else:
    print("[patch-rand-scope-ui] «+» visibility gate: already applied")

# 7. Гейт предупреждений: if (randOn) { setConfirmA → [randSub, randConn, randSub, randConn]
if 'if (randSub) { setConfirmA' not in t and 'if (randConn) { setConfirmA' not in t:
    seq = ["randSub", "randConn", "randSub", "randConn"]
    okc = 0
    for fv in seq:
        if "if (randOn) { setConfirmA" in t:
            t = t.replace("if (randOn) { setConfirmA", "if (" + fv + ") { setConfirmA", 1)
            okc += 1
    print(f"[patch-rand-scope-ui] warning gate: ok ({okc}/4)")
else:
    print("[patch-rand-scope-ui] warning gate: already applied")

# 8. Селектор скоупа в AdditionalRandomizationSection: state+fetch+save
if 'const [randScopeSel, setRandScopeSel]' not in t:
    old = '  const [open, setOpen] = useState(() => readStoredBool("olc-addrand-open-v1", false));'
    new = '''  const [open, setOpen] = useState(() => readStoredBool("olc-addrand-open-v1", false));
  const [randScopeSel, setRandScopeSel] = useState("both");
  useEffect(() => { void fetch("/api/settings/randomization/scope", { cache: "no-store" }).then((r) => r.json()).then((b: any) => { if (b && (b.rand_scope === "client_id" || b.rand_scope === "crypto" || b.rand_scope === "both")) setRandScopeSel(b.rand_scope); }).catch(() => {}); }, []);
  const saveRandScope = (s: string) => { setRandScopeSel(s); void fetch("/api/settings/randomization/scope", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ rand_scope: s }) }).catch(() => {}); };
  const scopeBtn = (val: string, label: string) => (
    <button type="button" onClick={() => saveRandScope(val)}
      className={"rounded-md border px-2 py-1 text-xs font-medium transition-colors duration-300 " + (randScopeSel === val ? "border-amber-500/60 bg-amber-500/15 text-amber-300" : "border-border text-muted-foreground hover:bg-muted")}>
      {label}
    </button>
  );'''
    if old in t:
        t = t.replace(old, new, 1)
        print("[patch-rand-scope-ui] scope selector state: ok")
    else:
        print("[patch-rand-scope-ui] WARN scope selector state: anchor nf")
else:
    print("[patch-rand-scope-ui] scope selector state: already applied")

# 9. Селектор скоупа — рендер (перед <KeyRotationSection />)
if 'Область действия рандомизации' not in t:
    old = '        <div className="border-l-2 border-amber-500/30 pl-3">\n          <KeyRotationSection />\n        </div>'
    new = '''        <div className="border-l-2 border-amber-500/30 pl-3 grid gap-2">
          <div className="grid gap-2 rounded-md border border-border bg-card/40 p-3">
            <div className="text-xs font-semibold text-foreground">🎯 Область действия рандомизации</div>
            <div className="text-[11px] text-muted-foreground">К чему применяется рандомизация (тип 1/2). По умолчанию — к обоим.</div>
            <div className="flex flex-wrap gap-2">
              {scopeBtn("both", "И client_id, и ключи")}
              {scopeBtn("client_id", "Только client_id (🎫)")}
              {scopeBtn("crypto", "Только ключи (🔌)")}
            </div>
            <div className="text-[10px] leading-snug text-muted-foreground">Определяет, где доступны режим «+» и предупреждения: client_id → 🎫 (подписка), ключи → 🔌 (подключение). Энфорсмент крипто-ключей — в разработке.</div>
          </div>
          <KeyRotationSection />
        </div>'''
    if old in t:
        t = t.replace(old, new, 1)
        print("[patch-rand-scope-ui] scope selector render: ok")
    else:
        print("[patch-rand-scope-ui] WARN scope selector render: anchor nf")
else:
    print("[patch-rand-scope-ui] scope selector render: already applied")

if t != orig:
    f.write_text(t)
    print("[patch-rand-scope-ui] OK: main.tsx updated")
else:
    print("[patch-rand-scope-ui] no changes")
PY
