#!/usr/bin/env bash
# Olc-cost-l frontend: при СВЁРНУТОЙ секции рандомизации (Выборочная / Глобальная
# «Subscription Randomization») показывать краткий статус-бейдж, чтобы пользователь
# не «терял» настройку после нажатия «Скрыть» (жалоба: «куда пропала глобальная
# рандомизация»). Idempotent. Target: manager src/main.tsx.
# Run ПОСЛЕ panel-subscription-ui (нужны анкоры заголовков секций).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-rand-collapse-hint] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard):
    global t, changed
    if guard in t:
        print(f"[patch-rand-collapse-hint] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-rand-collapse-hint] {label}: ok")
    else:
        print(f"[patch-rand-collapse-hint] WARN {label}: anchor not found")

# --- 1. Выборочная рандомизация: бейдж при свёрнутой секции ---
repl(
    '<div className="text-xs text-muted-foreground">Индивидуальные настройки рандомизации для каждого клиента</div>',
    '''<div className="text-xs text-muted-foreground">Индивидуальные настройки рандомизации для каждого клиента</div>
                {!selectiveRandomizationOpen && (() => {
                  const n = (state?.clients || []).filter((c: any) => c.randomization?.enabled).length;
                  return globalRandomizationEnabled
                    ? <div className="mt-0.5 text-[11px] font-medium text-amber-500">🎲 Перекрыта глобальной рандомизацией</div>
                    : n > 0
                      ? <div className="mt-0.5 text-[11px] font-medium text-emerald-500">🎲 Включена у {n} {n === 1 ? "клиента" : "клиентов"}</div>
                      : <div className="mt-0.5 text-[11px] text-muted-foreground">Выключена у всех клиентов</div>;
                })()}''',
    "selective hint",
    "Перекрыта глобальной рандомизацией",
)

# --- 2. Глобальная (Subscription Randomization): бейдж при свёрнутой секции ---
repl(
    '<div className="text-xs text-muted-foreground">Защита от enumeration через HMAC-SHA256 hash</div>',
    '''<div className="text-xs text-muted-foreground">Защита от enumeration через HMAC-SHA256 hash</div>
                {!subscriptionRandomizationOpen && (
                  globalRandomizationEnabled
                    ? <div className="mt-0.5 text-[11px] font-medium text-amber-500">🟢 Глобальная рандомизация включена</div>
                    : <div className="mt-0.5 text-[11px] text-muted-foreground">Глобальная рандомизация выключена</div>
                )}''',
    "global hint",
    "Глобальная рандомизация включена",
)

if changed:
    f.write_text(t)
    print("[patch-rand-collapse-hint] OK: main.tsx updated")
else:
    print("[patch-rand-collapse-hint] no changes")
PY
