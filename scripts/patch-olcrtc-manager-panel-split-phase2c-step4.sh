#!/usr/bin/env bash
# Phase 2C Step 4: Improve visual design of "Применить изменения" section + warm green button

set -e
TARGET="${1:-src/main.tsx}"

if ! [ -f "$TARGET" ]; then
  echo "[split-2c-step4] target not found: $TARGET" >&2
  exit 1
fi

# Idempotency check: search for the specific green button structure (not just any bg-emerald-600)
if grep -q "w-full rounded-lg bg-emerald-600.*Применить" "$TARGET" 2>/dev/null; then
  echo "[split-2c-step4] already applied" >&2
  exit 0
fi

python3 - "$TARGET" <<'PYSCRIPT'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    t = f.read()

# Find and replace the "Применить изменения" section
# Old structure: button on the right side with primary (blue) colors
old_section = '''                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <div>
                      <div className="font-medium">Применить изменения</div>
                      <p className="text-xs text-muted-foreground">Синхронизирует конфиг, логи и применяет роутинг</p>
                    </div>
                    <button
                      type="button"
                      className="rounded border border-primary bg-primary/10 px-4 py-2 text-sm font-medium text-primary hover:bg-primary/20 disabled:opacity-50"
                      disabled={saving}
                      onClick={() => void splitApplyAll()}
                    >
                      Применить
                    </button>
                  </div>
                  {splitAnalyzeMsg && (
                    <p className={`text-xs ${splitAnalyzeMsg.startsWith("✓") ? "text-emerald-400" : splitAnalyzeMsg.includes("...") ? "text-blue-400" : "text-red-400"}`}>
                      {splitAnalyzeMsg}
                    </p>
                  )}
                  <p className="text-[10px] text-muted-foreground">{t("splitRestartHint")}</p>
                </section>'''

# New structure: enhanced visual design with warm green button below text
new_section = '''                <section className="rounded-lg border-2 border-emerald-600/20 bg-gradient-to-br from-emerald-50/10 to-muted/20 p-4 space-y-3 shadow-sm">
                  <div>
                    <div className="font-semibold text-base">Применить изменения</div>
                    <p className="text-xs text-muted-foreground mt-1">Синхронизирует конфиг, логи и применяет роутинг</p>
                  </div>
                  <button
                    type="button"
                    className="w-full rounded-lg bg-emerald-600 px-6 py-3 text-base font-semibold text-white hover:bg-emerald-700 active:bg-emerald-800 disabled:opacity-50 disabled:cursor-not-allowed transition-colors shadow-sm"
                    disabled={saving}
                    onClick={() => void splitApplyAll()}
                  >
                    Применить
                  </button>
                  {splitAnalyzeMsg && (
                    <p className={`text-xs ${splitAnalyzeMsg.startsWith("✓") ? "text-emerald-600 font-medium" : splitAnalyzeMsg.includes("...") ? "text-blue-400" : "text-red-400"}`}>
                      {splitAnalyzeMsg}
                    </p>
                  )}
                  <p className="text-[10px] text-muted-foreground/80">{t("splitRestartHint")}</p>
                </section>'''

if old_section not in t:
    print("[split-2c-step4] anchor not found: Применить изменения section", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_section, new_section, 1)

print("[split-2c-step4] improved visual design of Apply section: ok", file=sys.stderr)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(t)
PYSCRIPT
