#!/usr/bin/env bash
# Olc-cost-l frontend fix: восстановить контролы системного профиля мостов.
# Регрессия: patch-olcrtc-manager-panel-bridge-fix-final.sh при переходе на
# карточки профилей ВЫКИНУЛ блок «Типы мостов / Автообновление / Обновить сейчас»
# для оригинального (системного) профиля (остались только i18n-строки). Возвращаем
# контролы прямо под карточкой системного профиля. «Обновить сейчас» показываем
# ВСЕГДА (юзер жаловался, что кнопка исчезает при автообновлении).
# Idempotent. Target: manager src/main.tsx. Run after bridge-fix-final.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-bridge-system-controls] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()

if 'olc-bridge-system-controls' in t:
    print("[patch-bridge-system-controls] already applied")
    sys.exit(0)

# Якорь: конец карточки системного профиля (radio + закрытие двух div) перед
# комментарием «Custom profile cards».
anchor = '''            <input type="radio" name="profile" checked={activeId === "system"} onChange={() => patchProfiles({ ...prof, active_profile: "system" })} />
          </div>
        </div>

        {/* Custom profile cards */}'''

controls = '''            <input type="radio" name="profile" checked={activeId === "system"} onChange={() => patchProfiles({ ...prof, active_profile: "system" })} />
          </div>
          {/* olc-bridge-system-controls: типы мостов / автообновление / обновить (восстановлено) */}
          <div className="mt-2 space-y-2 border-t border-border pt-2">
            <label className="grid gap-1 text-[11px] text-muted-foreground">
              Типы мостов
              <select
                className="h-8 rounded border border-border bg-background px-2 text-foreground"
                value={String(sys.types ?? "obfs4")}
                onChange={(e) => patchProfiles({ ...prof, system: { ...sys, types: e.target.value } })}
              >
                <option value="obfs4">obfs4</option>
                <option value="webtunnel">webTunnel</option>
                <option value="obfs4,webtunnel">obfs4 + webTunnel</option>
              </select>
            </label>
            <label className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <input
                type="checkbox"
                checked={Boolean(sys.auto_update)}
                onChange={(e) => patchProfiles({ ...prof, system: { ...sys, auto_update: e.target.checked } })}
              />
              Автообновление пула (cron, ~каждые 6ч)
            </label>
            <button
              type="button"
              className="rounded border border-border px-2 py-1 text-[11px] hover:bg-muted disabled:opacity-60"
              disabled={poolBusy || jobStatus === "running"}
              onClick={() => void refreshPool(String(sys.types ?? "obfs4"))}
            >
              Обновить пул сейчас
            </button>
            <p className="text-[10px] text-muted-foreground">
              Обновляет мосты выбранных типов из встроенных источников. obfs4 — быстрее;
              webtunnel — устойчивее к блокировкам (качается бинарь webtunnel-client).
            </p>
          </div>
        </div>

        {/* Custom profile cards */}'''

if anchor in t:
    t = t.replace(anchor, controls, 1)
    f.write_text(t)
    print("[patch-bridge-system-controls] OK: restored system profile controls")
else:
    print("[patch-bridge-system-controls] WARN: system profile card anchor not found (bridge-fix-final must run first)")
PY
