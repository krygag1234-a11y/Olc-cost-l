#!/usr/bin/env bash
# Olc-cost-l frontend: правки по приёмке №20:
# (#2) 🔌 scope-радио («Все инстансы»/«Только выбранные») — НЕ исчезают при
#      «Выключено», а затемняются (dimCls) и разблокируются при «+»/«Блокировать»
#      (глоб + выборочно).
# (#3) переименовать «🎫 Попытки подписки» → «🎫 Попытки подключения к подписке».
# (#4) кнопка «Очистить» у КАЖДОГО из 3 логов клиента (attempts/connections/active).
# Idempotent. Target: manager src/main.tsx. Run ПОСЛЕ rand-scope-ui.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-clogs-scope-polish] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
orig = t

def repl(old, new, label, guard=None):
    global t
    if guard is not None and guard in t:
        print(f"[patch-clogs-scope-polish] {label}: already applied"); return
    n = t.count(old)
    if n == 0:
        print(f"[patch-clogs-scope-polish] WARN {label}: anchor not found"); return
    if n > 1:
        print(f"[patch-clogs-scope-polish] WARN {label}: anchor not unique ({n})"); return
    t = t.replace(old, new, 1)
    print(f"[patch-clogs-scope-polish] {label}: ok")

# (#2a) Глобальный 🔌 scope-регион: всегда виден + затемнён при off
repl(
    '            {(!connOff || connKr) && (\n              <div className="grid gap-2 pl-5">',
    '            {(\n              <div className={"grid gap-2 pl-5" + dimCls(connOff && !connKr)}>',
    "G scope always+dim",
    guard='{(\n              <div className={"grid gap-2 pl-5" + dimCls(connOff && !connKr)}>',
)

# (#2b) Выборочный 🔌 scope-регион: всегда виден + затемнён при off
repl(
    '              {connEnforce && (\n                <div className="grid gap-2 pl-5">',
    '              {(\n                <div className={"grid gap-2 pl-5" + dimCls(connOff && !connKr)}>',
    "C scope always+dim",
    guard='{(\n                <div className={"grid gap-2 pl-5" + dimCls(connOff && !connKr)}>',
)

# (#3) Переименовать 🎫 Попытки подписки
repl(
    '<ClientLogPanel title="🎫 Попытки подписки" load={loadAttempts}',
    '<ClientLogPanel title="🎫 Попытки подключения к подписке" load={loadAttempts} onClear={clearAttempts}',
    "rename+onClear attempts",
    guard='title="🎫 Попытки подключения к подписке"',
)

# (#4) onClear к connections + active
repl(
    '<ClientLogPanel title="🔌 Попытки подключения к инстансам" load={loadConns}',
    '<ClientLogPanel title="🔌 Попытки подключения к инстансам" load={loadConns} onClear={clearConns}',
    "onClear conns",
    guard='load={loadConns} onClear={clearConns}',
)
repl(
    '<ClientLogPanel title="🔌 Подключения к инстансам (активны сейчас)" load={loadActive}',
    '<ClientLogPanel title="🔌 Подключения к инстансам (активны сейчас)" load={loadActive} onClear={clearConns}',
    "onClear active",
    guard='load={loadActive} onClear={clearConns}',
)

# (#4) clearAttempts/clearConns функции в ClientAccessLogModal (перед loadActive)
if 'const clearConns = async ()' not in t:
    anchor = '  const loadActive = useCallback(async (): Promise<React.ReactNode[]> => {'
    block = '''  const clearAttempts = async () => { try { await fetch(`/api/access/attempts/clear?client_id=${encodeURIComponent(cid)}`, { method: "POST" }); } catch { /* ignore */ } };
  const clearConns = async () => { try { await fetch(`/api/access/connections?clear=1&client_id=${encodeURIComponent(cid)}`, { cache: "no-store" }); } catch { /* ignore */ } };
'''
    if anchor in t:
        t = t.replace(anchor, block + anchor, 1)
        print("[patch-clogs-scope-polish] clear funcs: ok")
    else:
        print("[patch-clogs-scope-polish] WARN clear funcs: anchor not found")
else:
    print("[patch-clogs-scope-polish] clear funcs: already applied")

# (#4) onClear prop в сигнатуре ClientLogPanel + кнопка в шапке
repl(
    'function ClientLogPanel({ title, load, empty, autologi, liveKey, maxH, statusMode, hint }: { title: string; load: () => Promise<React.ReactNode[]>; empty: string; autologi: boolean; liveKey: string; maxH?: string; statusMode?: boolean; hint?: string }) {',
    'function ClientLogPanel({ title, load, empty, autologi, liveKey, maxH, statusMode, hint, onClear }: { title: string; load: () => Promise<React.ReactNode[]>; empty: string; autologi: boolean; liveKey: string; maxH?: string; statusMode?: boolean; hint?: string; onClear?: () => Promise<void> }) {',
    "ClientLogPanel signature onClear",
    guard='statusMode?: boolean; hint?: string; onClear?: () => Promise<void> }',
)

# кнопка «Очистить» в шапке ClientLogPanel (перед закрытием правого блока шапки)
repl(
    '''        <div className="text-xs font-semibold text-foreground">{title}</div>
        <div className="flex shrink-0 items-center gap-2">''',
    '''        <div className="text-xs font-semibold text-foreground">{title}</div>
        <div className="flex shrink-0 items-center gap-2">
          {onClear && <button type="button" className="inline-flex items-center rounded-md border border-destructive/40 px-2 py-0.5 text-[11px] text-destructive hover:bg-destructive/10" onClick={async () => { await onClear(); void refresh(true); }}>Очистить</button>}''',
    "ClientLogPanel Очистить button",
    guard='onClick={async () => { await onClear(); void refresh(true); }}>Очистить</button>',
)

if t != orig:
    f.write_text(t)
    print("[patch-clogs-scope-polish] OK: main.tsx updated")
else:
    print("[patch-clogs-scope-polish] no changes")
PY
