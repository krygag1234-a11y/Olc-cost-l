#!/usr/bin/env bash
# Olc-cost-l frontend: удобный выбор интервала автообновления подписки (в часах).
#
# Раньше поле refresh было свободным текстом "например 10m". olcbox управляет
# автообновлением подписки через заголовок profile-update-interval (ЧАСЫ, 1..720,
# опрос не чаще раза в час), который панель отдаёт из refresh (backend-патч
# subscription-update-interval). Поэтому заменяем 3 текстовых поля (глоб.
# настройки + 2 формы клиента) на пикер: кнопки 1ч/6ч/12ч/24ч + своё (часы) +
# сброс. Значение хранится как "Nh" (validateRefresh это принимает; refreshToHours
# переводит в часы). Пустое = дефолт olcbox (24ч). Легаси s/m/d показываем как есть.
#
# Idempotent. Target: main.tsx. Порядок: после golden-panel (любой поздний tsx-патч).
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-refresh-hours-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Компонент RefreshHoursPicker (перед function ClientSettingsFields) ---
if 'function RefreshHoursPicker(' not in t:
    anchor = 'function ClientSettingsFields({'
    comp = '''function RefreshHoursPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const presets = [1, 6, 12, 24];
  const raw = (value || "").trim();
  const m = /^(\\d+)h$/.exec(raw);
  const curHours = m ? parseInt(m[1], 10) : 0;
  const legacy = raw !== "" && curHours === 0;
  // Пусто = дефолт olcbox 24ч → подсвечиваем 24ч ЯВНО (не оставляем пустым/невыбранным).
  const effHours = curHours > 0 ? curHours : (legacy ? 0 : 24);
  const isPreset = presets.indexOf(effHours) >= 0;
  return (
    <div className="grid gap-2">
      <div className="flex flex-wrap items-center gap-2">
        {presets.map((h) => (
          <button key={h} type="button"
            className={effHours === h
              ? "rounded-md border border-primary bg-primary/10 px-3 py-1.5 text-sm text-primary"
              : "rounded-md border border-border bg-background px-3 py-1.5 text-sm text-muted-foreground hover:bg-muted"}
            onClick={() => onChange(h + "h")}>{h}ч</button>
        ))}
        <label className="flex items-center gap-1 text-sm text-muted-foreground">
          своё:
          <input type="number" min={1} max={720}
            className="h-9 w-20 rounded-md border border-border bg-background px-2 text-foreground outline-none focus:border-primary"
            value={!isPreset && curHours > 0 ? String(curHours) : ""}
            placeholder="ч"
            onChange={(e) => { const n = parseInt(e.target.value, 10); onChange(Number.isFinite(n) && n > 0 ? String(Math.min(720, n)) + "h" : ""); }} />
        </label>
        {raw !== "" && (
          <button type="button" className="rounded-md border border-border px-2 py-1.5 text-xs text-muted-foreground hover:bg-muted" onClick={() => onChange("")}>сброс</button>
        )}
      </div>
      <div className="text-[11px] text-muted-foreground">
        {legacy
          ? "Текущее значение «" + raw + "» — устаревший формат; olcbox округлит до часов. Выберите часы явно."
          : curHours > 0
            ? "Клиент (olcbox) автообновляет подписку раз в " + curHours + " ч."
            : "По умолчанию — раз в 24 ч (значение подставляется явно; отправляется заголовком profile-update-interval)."}
        {" "}olcbox проверяет не чаще раза в час и при заходе в приложение.
      </div>
    </div>
  );
}

'''
    t = t.replace(anchor, comp + anchor, 1)
    changed = True
    print("[patch-refresh-hours-ui] added RefreshHoursPicker component")
else:
    print("[patch-refresh-hours-ui] component already present")

# --- 2. Заменить 2 клиентских input (идентичны) на пикер ---
client_input = '''<input
          className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
          value={form.refresh}
          onChange={(event) => set({ refresh: event.target.value })}
          placeholder="например 10m"
        />'''
client_picker = '''<RefreshHoursPicker value={form.refresh} onChange={(v) => set({ refresh: v })} />'''
n_client = t.count(client_input)
if n_client > 0:
    t = t.replace(client_input, client_picker)
    changed = True
    print("[patch-refresh-hours-ui] replaced %d client refresh input(s)" % n_client)
elif 'RefreshHoursPicker value={form.refresh}' in t:
    print("[patch-refresh-hours-ui] client refresh picker already present")
else:
    print("[patch-refresh-hours-ui] WARN: client refresh input anchor not found")

# --- 3. Заменить глобальный input настроек на пикер ---
global_input = '''<input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={settingsForm.refresh}
                  onChange={(event) => setSettingsForm({ ...settingsForm, refresh: event.target.value })}
                  placeholder="например 10m"
                />'''
global_picker = '''<RefreshHoursPicker value={settingsForm.refresh} onChange={(v) => setSettingsForm({ ...settingsForm, refresh: v })} />'''
if global_input in t:
    t = t.replace(global_input, global_picker, 1)
    changed = True
    print("[patch-refresh-hours-ui] replaced global refresh input")
elif 'RefreshHoursPicker value={settingsForm.refresh}' in t:
    print("[patch-refresh-hours-ui] global refresh picker already present")
else:
    print("[patch-refresh-hours-ui] WARN: global refresh input anchor not found")

if changed:
    f.write_text(t)
    print("[patch-refresh-hours-ui] OK: main.tsx updated")
else:
    print("[patch-refresh-hours-ui] no changes (idempotent)")
PY
