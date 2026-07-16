#!/usr/bin/env bash
# Olc-cost-l frontend: секция «Бекап данных» в модалке общих настроек.
#   Кнопки Экспорт (скачать JSON со ВСЕМИ данными) и Импорт (восстановить).
#   Работает с бекенд-роутами /api/backup/{export,import}.
#   Данные хранятся ТОЛЬКО на устройстве пользователя (написано прямо в UI).
#
# ВАЖНО: если добавляете новую настройку/состояние в UI, которое должно
# переживать переустановку — проверьте, что оно попадает в бэкап на бэкенде
# (config.json или backupExtraFiles() в patch-olcrtc-manager-backup-api.sh).
# См. docs/BACKUP.md.
#
# Idempotent. Target: manager src/main.tsx. Run near end of frontend patches.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-backup-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Компонент BackupSection (перед ComponentSettingsModal) ---
comp_anchor = 'function ComponentSettingsModal({'
comp_block = r'''// ============================================================================
// Olc-cost-l: секция «Бекап данных» в общих настройках.
// Экспорт/импорт ВСЕХ данных панели (серверы, инстансы, клиенты, настройки) в
// один JSON. Данные хранятся ТОЛЬКО на устройстве пользователя. Импорт устойчив
// к смене версий панели (бэкенд делает schema-независимый deep-merge).
//
// !!! ПРИ ИЗМЕНЕНИИ UI/НАСТРОЕК: новые данные, которые должны переживать
// переустановку, должны попадать в бэкап на бэкенде (config.json или
// backupExtraFiles() в patch-olcrtc-manager-backup-api.sh). См. docs/BACKUP.md.
// ============================================================================
function BackupSection() {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement | null>(null);

  const doExport = async () => {
    setBusy(true); setErr(null); setMsg(null);
    try {
      const res = await fetch("/api/backup/export", { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      const stamp = new Date().toISOString().replace(/[:T]/g, "-").slice(0, 19);
      a.download = "olc-backup-" + stamp + ".json";
      document.body.appendChild(a); a.click(); a.remove();
      URL.revokeObjectURL(url);
      setMsg("Бекап скачан. Храните файл в надёжном месте — в нём все ваши данные.");
    } catch (e: any) {
      setErr("Не удалось экспортировать: " + (e?.message || String(e)));
    } finally { setBusy(false); }
  };

  const doImport = async (file: File) => {
    setBusy(true); setErr(null); setMsg(null);
    try {
      const text = await file.text();
      const res = await fetch("/api/backup/import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: text,
      });
      const data = await res.json().catch(() => ({} as any));
      if (!res.ok) throw new Error((data && data.error) || ("HTTP " + res.status));
      const restored = (data && data.restored) || [];
      setMsg("Восстановлено: " + (restored.join(", ") || "нет данных") + ". " + ((data && data.note) || ""));
    } catch (e: any) {
      setErr("Не удалось импортировать: " + (e?.message || String(e)));
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  return (
    <section className="grid gap-3 rounded-md border border-border bg-background p-4">
      <div className="text-sm font-medium text-foreground">Бекап данных</div>
      <div className="text-xs text-muted-foreground">
        Экспортируйте все свои данные (серверы, инстансы, клиенты, все настройки) в один
        файл и восстановите их после переустановки или на новом VPS. Импорт устойчив к
        обновлению панели. Эта информация хранится ИСКЛЮЧИТЕЛЬНО на ваших устройствах, где
        находится панель — сервер её никуда не отправляет.
      </div>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
          disabled={busy}
          onClick={doExport}
        >
          Экспортировать (скачать JSON)
        </button>
        <button
          type="button"
          className="inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60"
          disabled={busy}
          onClick={() => fileRef.current?.click()}
        >
          Импортировать (выбрать JSON)
        </button>
        <input
          ref={fileRef}
          type="file"
          accept="application/json,.json"
          className="hidden"
          onChange={(e) => { const file = e.target.files && e.target.files[0]; if (file) doImport(file); }}
        />
      </div>
      {msg && <div className="text-xs text-green-500 whitespace-pre-wrap">{msg}</div>}
      {err && <div className="text-xs text-red-500 whitespace-pre-wrap">{err}</div>}
      <div className="text-[11px] text-muted-foreground">
        После импорта перезапустите панель, чтобы применить восстановленные данные.
      </div>
    </section>
  );
}

'''
if 'function BackupSection()' in t:
    print("[patch-backup-ui] BackupSection component already present")
elif comp_anchor in t:
    t = t.replace(comp_anchor, comp_block + comp_anchor, 1)
    changed = True
    print("[patch-backup-ui] added BackupSection component")
else:
    print("[patch-backup-ui] WARN: ComponentSettingsModal anchor not found — skip component")

# --- 2. Рендер <BackupSection /> в модалке настроек (после секции интерфейса) ---
render_anchor = '''                  <option value="ru">Русский</option>
                  <option value="en">English</option>
                </select>
              </label>
            </section>'''
render_add = render_anchor + '''

            <BackupSection />'''
if '<BackupSection />' in t:
    print("[patch-backup-ui] <BackupSection /> already rendered")
elif render_anchor in t:
    t = t.replace(render_anchor, render_add, 1)
    changed = True
    print("[patch-backup-ui] rendered <BackupSection /> in settings modal")
else:
    print("[patch-backup-ui] WARN: settings-modal anchor (language select) not found — skip render")

if changed:
    f.write_text(t)
    print("[patch-backup-ui] OK: main.tsx updated")
else:
    print("[patch-backup-ui] no changes (idempotent)")
PY
