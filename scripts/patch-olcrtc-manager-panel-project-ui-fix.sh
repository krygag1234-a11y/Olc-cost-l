#!/usr/bin/env bash
# Project modal: stack card + clearer git error (idempotent even if ui-v7 marker present).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-project-ui-fix' "$MAIN_TSX" && { echo "[patch-panel-project-ui-fix] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

stack_block = '''              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Стек сервисов</div>
                <div className="text-lg font-semibold">
                  {(stack.enabled as number) ?? (patches.applied_estimate as number) ?? 0}/{(stack.total as number) ?? (patches.total_scripts as number) ?? 4}
                </div>
                <div className="mt-1 flex flex-wrap gap-1 text-[10px]">
                  {((stack.items as { id?: string; enabled?: boolean; label?: string }[]) ?? []).map((it) => (
                    <span key={it.id} className={`rounded px-1.5 py-0.5 ${it.enabled ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-600/30"}`}>
                      {it.label ?? it.id}
                    </span>
                  ))}
                </div>
                <p className="mt-1 text-[10px] text-muted-foreground">скриптов патчей: {patches.applied_estimate ?? 0}/{patches.total_scripts ?? 0}</p>
              </div>'''

old_patches = '''              <div className="rounded border border-border p-3">
                <div className="text-xs text-muted-foreground">Патчи (скрипты)</div>
                <div className="text-lg font-semibold">
                  {patches.applied_estimate ?? 0}/{patches.total_scripts ?? 0}
                </div>
                <div className="text-xs text-muted-foreground">оценка по наличию бинарников</div>
              </div>'''

if old_patches in t:
    t = t.replace(old_patches, stack_block, 1)
elif 'Стек сервисов' not in t:
    print("[patch-panel-project-ui-fix] patches card not found", file=sys.stderr)
    sys.exit(1)

if 'const stack = (status?.stack' not in t:
    t = t.replace(
        '  const patches = (status?.patches as { total_scripts?: number; applied_estimate?: number }) ?? {};\n',
        '  const patches = (status?.patches as { total_scripts?: number; applied_estimate?: number; enabled?: number; total?: number; items?: { id?: string; label?: string; enabled?: boolean }[] }) ?? {};\n'
        '  const stack = (status?.stack ?? status?.patches) as { enabled?: number; total?: number; items?: { id?: string; label?: string; enabled?: boolean }[] } ?? {};\n',
        1,
    )

git_old = '''                ) : (
                  <span className="text-muted-foreground"> (remote недоступен — проверьте git на VPS)</span>
                )}'''
git_new = '''                ) : (
                  <span className="text-muted-foreground">
                    {" "}
                    (origin/main недоступен — git fetch с VPS или safe.directory; локальный SHA: {status?.local_sha ? "есть" : "нет"})
                  </span>
                )}'''
if git_old in t:
    t = t.replace(git_old, git_new, 1)

if '/* olc-project-ui-fix */' not in t:
    t = t.replace('/* olc-panel-ui-v7 */', '/* olc-panel-ui-v7 */\n/* olc-project-ui-fix */', 1)

p.write_text(t)
print("[patch-panel-project-ui-fix] ok")
PY
