#!/usr/bin/env bash
# Phase 0 (autosave) — general settings modal (App-level server name/port/path).
# Removes the "Сохранить настройки" button. This modal is validated (name, port),
# so we autosave on modal close + on page unload, only when the form is valid
# (invalid values are silently skipped — they could never be saved anyway).
# Footer shows a status indicator instead of a Save button.
# Idempotent. Target: manager src/main.tsx. Run after addon-settings-autosave.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-general-autosave] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-general-autosave] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-general-autosave] {label}: ok")
    else:
        print(f"[patch-general-autosave] WARN {label}: anchor not found")

# --- 1. Add a validated silent autosave next to saveSettings ---
repl(
    '''  const saveSettings = async () => {
    setBusy(true);
    setNotice("");''',
    '''  const settingsFormValid = () => {
    const port = Number(settingsForm.port);
    return Boolean(settingsForm.name.trim()) && Number.isInteger(port) && port > 0 && port <= 65535;
  };
  // Autosave used on close/unload: silent, validated, no form reset (avoids input churn).
  const saveSettingsAuto = async () => {
    if (!settingsFormValid()) return;
    try {
      const port = Number(settingsForm.port);
      await request("/api/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: settingsForm.name.trim(),
          port,
          subscription_path: settingsForm.subscription_path.trim(),
          refresh: cleanRefresh(settingsForm.refresh),
        }),
      });
      loadState().catch(() => {});
      loadAudit().catch(() => {});
    } catch {
      /* best-effort; keep silent on close */
    }
  };

  const saveSettings = async () => {
    setBusy(true);
    setNotice("");''',
    "saveSettingsAuto helper",
    guard='const saveSettingsAuto = async () =>',
)

# --- 2. Autosave on page unload while the settings modal is open ---
repl(
    '''  const openSettings = async () => {
    setShowSettings(true);''',
    '''  useEffect(() => {
    if (!showSettings) return;
    const onUnload = () => { void saveSettingsAuto(); };
    window.addEventListener("beforeunload", onUnload);
    return () => window.removeEventListener("beforeunload", onUnload);
  });

  const openSettings = async () => {
    setShowSettings(true);''',
    "settings unload autosave effect",
    guard='const onUnload = () => { void saveSettingsAuto(); };',
)

# --- 3. Both close handlers flush the autosave first ---
repl(
    "        <Modal wide title={t('settings')} onClose={() => setShowSettings(false)}>",
    "        <Modal wide title={t('settings')} onClose={() => { void saveSettingsAuto(); setShowSettings(false); }}>",
    "modal onClose autosave",
)
repl(
    "                onClick={() => { setShowAutodetectInline(false); setShowSettings(false); }}",
    "                onClick={() => { void saveSettingsAuto(); setShowAutodetectInline(false); setShowSettings(false); }}",
    "footer close autosave",
)

# --- 4. Replace the Save button with an autosave status hint ---
repl(
    '''              <button
                className="inline-flex h-9 items-center gap-2 rounded-md bg-primary px-3 text-sm font-medium text-black hover:bg-primary/90 disabled:opacity-60"
                disabled={busy}
                onClick={saveSettings}
              >
                <Settings className="h-4 w-4" />
                {t('saveSettings')}
              </button>''',
    '''              <span className="inline-flex h-9 items-center gap-2 text-xs text-muted-foreground">
                {settingsFormValid()
                  ? "Изменения сохраняются автоматически при закрытии"
                  : <span className="text-destructive">Проверьте название и порт — пока не сохраняется</span>}
              </span>''',
    "replace general save button with status",
    guard='Изменения сохраняются автоматически при закрытии',
)

if changed:
    f.write_text(t)
print("[patch-general-autosave] ok")
PY
