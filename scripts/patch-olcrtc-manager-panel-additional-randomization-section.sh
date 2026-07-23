#!/usr/bin/env bash
# Olc-cost-l frontend: обернуть «♻️ Автосмена ключей» (KeyRotationSection) в
# ОТДЕЛЬНУЮ сворачиваемую секцию «Дополнительные функции рандомизации» — контейнер
# под будущие расширенные настройки рандомизации (напр. область действия
# рандомизации ключей: любая рандомизация / только client_id / только крипто-ключи).
# Секция собственную свёртку хранит в localStorage. Idempotent. Target: main.tsx.
# Run ПОСЛЕ panel-key-rotation-ui (нужен компонент KeyRotationSection + место рендера).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-additional-rand] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Компонент-обёртка AdditionalRandomizationSection (перед function App) ---
comp_guard = 'function AdditionalRandomizationSection('
comp_anchor = 'function App()'
comp_block = r'''// ============================================================================
// Olc-cost-l: «Дополнительные функции рандомизации» — контейнер рядом с блоками
// рандомизации (выборочная / глобальная). Сейчас содержит «♻️ Автосмена ключей».
// Задел под будущие расширенные настройки рандомизации. Сворачивается отдельно
// (localStorage olc-addrand-open-v1), чтобы не удлинять модалку настроек.
// ============================================================================
function AdditionalRandomizationSection() {
  const [open, setOpen] = useState(() => readStoredBool("olc-addrand-open-v1", false));
  const toggle = () => { const v = !open; setOpen(v); writeStoredBool("olc-addrand-open-v1", v); };
  return (
    <div className="grid gap-2 rounded-md border border-border bg-card/30 p-3">
      <div className="flex items-center justify-between gap-2">
        <div>
          <div className="text-sm font-semibold text-foreground">🧩 Дополнительные функции рандомизации</div>
          <div className="text-xs text-muted-foreground">Расширенные возможности поверх рандомизации подписок/ключей</div>
          {!open && <div className="mt-0.5 text-[11px] text-muted-foreground">Внутри: ♻️ Автосмена ключей</div>}
        </div>
        <button
          type="button"
          className="rounded bg-amber-500/10 border border-amber-500/30 px-2 py-1 text-xs text-amber-600 hover:bg-amber-500/20 transition-colors"
          onClick={toggle}
        >
          {open ? "Скрыть" : "Настроить"}
        </button>
      </div>
      {open && (
        <div className="border-l-2 border-amber-500/30 pl-3">
          <KeyRotationSection />
        </div>
      )}
    </div>
  );
}

'''
if comp_guard in t:
    print("[patch-additional-rand] component: already applied")
elif comp_anchor in t:
    t = t.replace(comp_anchor, comp_block + comp_anchor, 1)
    changed = True
    print("[patch-additional-rand] component: ok")
else:
    print("[patch-additional-rand] WARN component: anchor 'function App()' not found")

# --- 2. Место рендера: KeyRotationSection -> AdditionalRandomizationSection ---
render_old = '<div className="py-2"><KeyRotationSection /></div>'
render_new = '<div className="py-2"><AdditionalRandomizationSection /></div>'
if render_new in t:
    print("[patch-additional-rand] render: already applied")
elif render_old in t:
    t = t.replace(render_old, render_new, 1)
    changed = True
    print("[patch-additional-rand] render: ok")
else:
    print("[patch-additional-rand] WARN render: anchor not found")

if changed:
    f.write_text(t)
    print("[patch-additional-rand] OK: main.tsx updated")
else:
    print("[patch-additional-rand] no changes")
PY
