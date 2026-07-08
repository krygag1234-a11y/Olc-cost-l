#!/usr/bin/env bash
# Phase 0 (autosave) — addon settings modal (ComponentSettingsModal).
# Removes the "Сохранить" button; changes autosave automatically:
#   - debounced ~1s after any edit,
#   - immediately on modal close and on page unload/reload.
# Shows a "сохранено ✓ / сохраняю…" status indicator instead of a button.
# Behavior of save() (payload shaping for webtunnel etc.) is reused unchanged.
# Idempotent. Target: manager src/main.tsx. Run after addon-settings-ui.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-addon-autosave] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-addon-autosave] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-addon-autosave] {label}: ok")
    else:
        print(f"[patch-addon-autosave] WARN {label}: anchor not found")

# --- 1. Add autosave plumbing right after setStr/setBool definitions ---
repl(
    '''  const setStr = (key: string, value: string) => setSettings((s) => ({ ...s, [key]: value }));
  const setBool = (key: string, value: boolean) => setSettings((s) => ({ ...s, [key]: value }));''',
    '''  // --- Autosave (Phase 0): no Save button; persist changes automatically. ---
  const saveRef = useRef<() => Promise<void>>(async () => {});
  const dirtyRef = useRef(false);
  const autoTimer = useRef<number | null>(null);
  const markDirtyAndSchedule = () => {
    if (loading) return; // don't autosave while initial load is populating state
    dirtyRef.current = true;
    if (autoTimer.current) window.clearTimeout(autoTimer.current);
    autoTimer.current = window.setTimeout(() => {
      dirtyRef.current = false;
      void saveRef.current();
    }, 1000);
  };
  const flushSave = () => {
    if (autoTimer.current) {
      window.clearTimeout(autoTimer.current);
      autoTimer.current = null;
    }
    if (dirtyRef.current) {
      dirtyRef.current = false;
      void saveRef.current();
    }
  };
  const setStr = (key: string, value: string) => { setSettings((s) => ({ ...s, [key]: value })); markDirtyAndSchedule(); };
  const setBool = (key: string, value: boolean) => { setSettings((s) => ({ ...s, [key]: value })); markDirtyAndSchedule(); };''',
    "autosave plumbing",
    guard='markDirtyAndSchedule',
)

# --- 2. Keep saveRef current + save on unload; flush on unmount ---
# Anchor on the existing effect that resets instanceDefaultsOpen per feature.
repl(
    '''  useEffect(() => {
    setInstanceDefaultsOpen(false);
  }, [feature]);''',
    '''  useEffect(() => {
    setInstanceDefaultsOpen(false);
  }, [feature]);

  // Keep the latest save fn in a ref so timers/unload always call the current one.
  useEffect(() => {
    saveRef.current = save;
  });
  // Persist on page unload/reload and flush any pending debounce on unmount.
  useEffect(() => {
    const onUnload = () => { if (dirtyRef.current) { dirtyRef.current = false; void saveRef.current(); } };
    window.addEventListener("beforeunload", onUnload);
    return () => {
      window.removeEventListener("beforeunload", onUnload);
      flushSave();
    };
  }, []);''',
    "saveRef + unload effects",
    guard='window.addEventListener("beforeunload", onUnload);',
)

# --- 3. Flush pending save when closing the modal (wrap onClose in the footer) ---
repl(
    '''        {msg && <p className={`text-xs ${msg === t("saved") ? "text-emerald-400" : "text-destructive"}`}>{msg}</p>}
        <div className="flex justify-end gap-2">
          <button
            type="button"
            className="rounded-md border border-border px-3 py-2 text-sm hover:bg-muted"
            onClick={onClose}
          >
            {t("close")}
          </button>
          <button
            type="button"
            disabled={loading || saving}
            className="rounded-md border border-primary bg-primary/20 px-3 py-2 text-sm text-primary disabled:opacity-50"
            onClick={() => void save()}
          >
            {saving ? "…" : t("save")}
          </button>
        </div>''',
    '''        <div className="flex items-center justify-between gap-2">
          <span className="text-xs">
            {saving
              ? <span className="text-muted-foreground">Сохраняю…</span>
              : msg === t("saved")
                ? <span className="text-emerald-400">Сохранено ✓</span>
                : msg
                  ? <span className="text-destructive">{msg}</span>
                  : <span className="text-muted-foreground">Изменения сохраняются автоматически</span>}
          </span>
          <button
            type="button"
            className="rounded-md border border-border px-3 py-2 text-sm hover:bg-muted"
            onClick={() => { flushSave(); onClose(); }}
          >
            {t("close")}
          </button>
        </div>''',
    "replace save button with autosave status",
    guard='Изменения сохраняются автоматически',
)

if changed:
    f.write_text(t)
print("[patch-addon-autosave] ok")
PY
