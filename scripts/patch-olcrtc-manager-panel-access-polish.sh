#!/usr/bin/env bash
# Olc-cost-l frontend: полировка контроля доступа/рандомизации по приёмке №20:
# (1) БАГ: сохранение mode=keyrand откатывалось (reflect обрабатывал только
#     enforce/monitor|off) → 🎫 «+» не включался / мигал. Фикс reflect.
# (2) «+»: активное состояние = зелёная заливка + ЖЁЛТАЯ обводка (жёлтый=идентичность
#     «+»); плавная смена цвета (transition-all) + анимация нажатия (active:scale-95).
# (3) Плавная смена цвета обводки у кнопок режимов (transition-colors).
# (4) «Включить контроль доступа»: чекбокс → кнопка.
# (5) Настройка «Блокировать управление при сохранении» (общие настройки,
#     localStorage olc-ctrl-lock-v1, дефолт вкл) — при выкл busy не блокирует UI.
# (6) Логи клиента «активны сейчас»: живой ICE-сигнал (как в Info) — быстрее грейса.
# Idempotent. Target: manager src/main.tsx. Run ПОСЛЕ panel-keyrand-plus-conn.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-access-polish] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None, all=False):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-access-polish] {label}: already applied")
        return
    n = t.count(old)
    if n == 0:
        print(f"[patch-access-polish] WARN {label}: anchor not found")
        return
    if not all and n > 1:
        print(f"[patch-access-polish] WARN {label}: anchor not unique ({n})")
        return
    t = t.replace(old, new, -1 if all else 1)
    changed = True
    print(f"[patch-access-polish] {label}: ok ({n})")

# (1) БАГ keyrand reflect
repl(
    'setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : "monitor");',
    'setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : b.mode === "keyrand" ? "keyrand" : "monitor");',
    "G mode reflect keyrand",
    guard='setMode(b.mode === "enforce" ? "enforce" : b.mode === "keyrand" ? "keyrand" : "monitor")',
)
repl(
    'setMode(cc.mode === "enforce" ? "enforce" : "off");',
    'setMode(cc.mode === "enforce" ? "enforce" : cc.mode === "keyrand" ? "keyrand" : "off");',
    "C mode reflect keyrand",
    guard='setMode(cc.mode === "enforce" ? "enforce" : cc.mode === "keyrand" ? "keyrand" : "off")',
)

# (2) «+» активная заливка/обводка + анимации (4 кнопки: 2 актив, 2 неактив фрагмента)
repl(
    'border border-emerald-600/60 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300',
    'border border-amber-500/70 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300 transition-all duration-300 active:scale-95',
    "plus active style",
    guard='border border-amber-500/70 bg-emerald-500/15 px-3 py-1 font-medium text-emerald-300 transition-all',
    all=True,
)
repl(
    'border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 hover:bg-amber-500/25',
    'border border-amber-500/60 bg-amber-500/15 px-3 py-1 font-medium text-amber-300 transition-all duration-300 active:scale-95 hover:bg-amber-500/25',
    "plus inactive style",
    guard='bg-amber-500/15 px-3 py-1 font-medium text-amber-300 transition-all',
    all=True,
)

# (3) Плавная смена цвета у кнопок режимов (px-2 фрагменты)
repl(
    'rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300',
    'rounded-md border border-emerald-600/60 bg-emerald-500/15 px-2 py-1 font-medium text-emerald-300 transition-colors duration-300',
    "mode btn emerald transition",
    guard='px-2 py-1 font-medium text-emerald-300 transition-colors',
    all=True,
)
repl(
    'rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300',
    'rounded-md border border-red-500/60 bg-red-500/15 px-2 py-1 font-medium text-red-300 transition-colors duration-300',
    "mode btn red transition",
    guard='px-2 py-1 font-medium text-red-300 transition-colors',
    all=True,
)
repl(
    'rounded-md border border-border px-2 py-1 text-muted-foreground hover:bg-muted"',
    'rounded-md border border-border px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"',
    "mode btn inactive transition",
    guard='px-2 py-1 text-muted-foreground transition-colors duration-300 hover:bg-muted"',
    all=True,
)

# (4) «Включить контроль доступа»: чекбокс -> кнопка
repl(
    '''      <label className="flex items-center gap-2 text-sm font-medium text-foreground">
        <input type="checkbox" checked={enabled} disabled={busy}
          onChange={(e) => { setEnabled(e.target.checked); void saveSettings({ enabled: e.target.checked }); }} />
        Включить контроль доступа
      </label>''',
    '''      <button type="button" disabled={busy}
        onClick={() => { const v = !enabled; setEnabled(v); void saveSettings({ enabled: v }); }}
        className={"inline-flex w-fit items-center gap-2 rounded-md border px-3 py-1.5 text-sm font-medium transition-colors duration-300 " + (enabled ? "border-emerald-600/60 bg-emerald-500/15 text-emerald-300" : "border-border text-muted-foreground hover:bg-muted")}>
        <span>{enabled ? "🔓" : "🔒"}</span> {enabled ? "Контроль доступа включён" : "Включить контроль доступа"}
      </button>''',
    "enable checkbox->button",
    guard='{enabled ? "Контроль доступа включён" : "Включить контроль доступа"}',
)

# (5) busy-lock: derived busy в двух компонентах + переключатель в общих настройках
repl(
    '  const [newHwid, setNewHwid] = useState("");\n  const [busy, setBusy] = useState(false);',
    '  const [newHwid, setNewHwid] = useState("");\n  const [busyRaw, setBusy] = useState(false);\n  const busy = busyRaw && readStoredBool("olc-ctrl-lock-v1", true);',
    "G busy-lock",
    guard='const [newHwid, setNewHwid] = useState("");\n  const [busyRaw, setBusy] = useState(false);',
)
repl(
    '  const [newConnBan, setNewConnBan] = useState("");\n  const [autolog, setAutolog] = useState(true);\n  const [busy, setBusy] = useState(false);',
    '  const [newConnBan, setNewConnBan] = useState("");\n  const [autolog, setAutolog] = useState(true);\n  const [busyRaw, setBusy] = useState(false);\n  const busy = busyRaw && readStoredBool("olc-ctrl-lock-v1", true);',
    "C busy-lock",
    guard='const [newConnBan, setNewConnBan] = useState("");\n  const [autolog, setAutolog] = useState(true);\n  const [busyRaw, setBusy] = useState(false);',
)

# компонент-переключатель CtrlLockToggle (перед function App)
repl(
    'function App()',
    '''function CtrlLockToggle() {
  const [on, setOn] = useState(() => readStoredBool("olc-ctrl-lock-v1", true));
  return (
    <div className="flex items-center justify-between border-b border-border py-2">
      <div>
        <div className="text-sm font-medium">Блокировать управление при сохранении</div>
        <div className="text-xs text-muted-foreground">Защита от двойных нажатий: кнопки/поля на миг блокируются во время сохранения. Выключите, если мешает при быстром переключении.</div>
      </div>
      <label className="inline-flex items-center gap-2 text-xs cursor-pointer">
        <input type="checkbox" checked={on} onChange={() => { const v = !on; setOn(v); writeStoredBool("olc-ctrl-lock-v1", v); }} className="cursor-pointer" />
        <span className={on ? "text-emerald-600 font-medium" : ""}>{on ? "Вкл" : "Выкл"}</span>
      </label>
    </div>
  );
}

function App()''',
    "CtrlLockToggle component",
    guard="function CtrlLockToggle() {",
)
# рендер переключателя после блока «Автологи»
repl(
    '''                <span className={autologi ? "text-emerald-600 font-medium" : ""}>{autologi ? "Вкл" : "Выкл"}</span>
              </label>
            </div>''',
    '''                <span className={autologi ? "text-emerald-600 font-medium" : ""}>{autologi ? "Вкл" : "Выкл"}</span>
              </label>
            </div>
            <CtrlLockToggle />''',
    "CtrlLockToggle render",
    guard="<CtrlLockToggle />",
)

# (6) Логи клиента «активны сейчас»: ICE-сигнал (быстрее грейса)
repl(
    '''  const loadActive = useCallback(async (): Promise<React.ReactNode[]> => {
    const d = await fetch("/api/state", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ clients: [] }));
    const lc = (d.clients || []).find((x: any) => x.client_id === cid);
    const byDev: Record<string, { inst: string; at: string }> = {};
    (lc?.locations || []).forEach((loc: any) => {
      const inst = loc.name || loc.room_id;
      const at = (loc.runtime && loc.runtime.peer_at) || "";
      ((loc.runtime && loc.runtime.peer_devices) || []).forEach((dev: string) => {
        if (!byDev[dev] || at > byDev[dev].at) byDev[dev] = { inst, at };
      });
    });
    return Object.keys(byDev).map((dev, i) => (
      <div key={"act-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
        <span className="text-emerald-400">●</span> {dev} <span className="text-muted-foreground">→</span> {byDev[dev].inst}
      </div>
    ));
  }, [cid]);''',
    '''  const loadActive = useCallback(async (): Promise<React.ReactNode[]> => {
    const d = await fetch("/api/state", { cache: "no-store" }).then((r) => r.json()).catch(() => ({ clients: [] }));
    const lc = (d.clients || []).find((x: any) => x.client_id === cid);
    const locs = (lc?.locations || []);
    // Живой сигнал здоровья по инстансам с активными пирами: ядро НЕ логирует
    // ICE-disconnect, но логирует «control missed pong»/«unhealthy»/«reason=liveness»
    // — ПЕРВЫЙ признак обрыва (~10-30с), раньше обнуления peer_count.
    const withPeers = locs.filter((loc: any) => (((loc.runtime && loc.runtime.peer_devices) || []).length) > 0);
    const badByRoom: Record<string, boolean> = {};
    await Promise.all(withPeers.map(async (loc: any) => {
      try {
        const q = new URLSearchParams({ client_id: cid, room_id: String(loc.room_id), transport: loc.transport || "" });
        const b = await fetch(`/api/logs/?${q.toString()}`, { cache: "no-store" }).then((r) => r.json());
        const lines = (b.logs || b.lines || []) as any[];
        let up = ""; let bad = "";
        for (const ln of lines) {
          const s = typeof ln === "string" ? ln : (ln.line || "");
          const tm = (ln && ln.time) || "";
          if (s.includes("peer connected: device=")) up = tm;
          else if (s.includes("control missed pong") || s.includes("control unhealthy") || s.includes("reason=liveness")) bad = tm;
        }
        badByRoom[String(loc.room_id)] = !!(bad && bad > up);
      } catch { /* ignore */ }
    }));
    const byDev: Record<string, { inst: string; at: string; bad: boolean }> = {};
    locs.forEach((loc: any) => {
      const inst = loc.name || loc.room_id;
      const at = (loc.runtime && loc.runtime.peer_at) || "";
      const bad = !!badByRoom[String(loc.room_id)];
      ((loc.runtime && loc.runtime.peer_devices) || []).forEach((dev: string) => {
        if (!byDev[dev] || at > byDev[dev].at) byDev[dev] = { inst, at, bad };
      });
    });
    return Object.keys(byDev).map((dev, i) => {
      const bad = byDev[dev].bad;
      return (
        <div key={"act-" + i} className="whitespace-pre-wrap break-words leading-relaxed">
          <span className={bad ? "text-amber-400" : "text-emerald-400"}>{bad ? "◌" : "●"}</span> {dev} <span className="text-muted-foreground">→</span> {byDev[dev].inst}{bad ? <span className="text-amber-500 text-[10px]"> · обрыв связи (ядро закроет по liveness, до ~1.5 мин)</span> : null}
        </div>
      );
    });
  }, [cid]);''',
    "client-logs active ICE",
    guard="Живой сигнал здоровья по инстансам с активными пирами",
)

if changed:
    f.write_text(t)
    print("[patch-access-polish] OK: main.tsx updated")
else:
    print("[patch-access-polish] no changes")
PY
