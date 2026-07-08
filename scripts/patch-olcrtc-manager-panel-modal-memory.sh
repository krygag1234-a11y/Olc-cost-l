#!/usr/bin/env bash
# Remember which modal the user had open and restore it after a page reload.
# Generic: one localStorage descriptor (olc-active-modal-v1) captures whichever
# App-level modal is open (settings / create / edit client / create+edit location
# / QR / client logs / instance logs). A restore effect reopens it after client
# state loads, re-resolving client/location by id + room_id. Addon feature
# log/settings modals persist separately (olc-active-feature-modal-v1) in
# FeaturesPanel. Idempotent. Target: manager src/main.tsx. Run last.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-modal-memory] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-modal-memory] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-modal-memory] {label}: ok")
    else:
        print(f"[patch-modal-memory] WARN {label}: anchor not found")

# --- 0. usePersistedOpen hook: a drop-in useState<boolean> that remembers itself ---
repl(
    'function readStoredBool(key: string, fallback = false) {',
    '''function usePersistedOpen(key: string): [boolean, (v: boolean | ((p: boolean) => boolean)) => void] {
  const [open, setOpenRaw] = useState(() => readStoredBool(key, false));
  const setOpen = useCallback((v: boolean | ((p: boolean) => boolean)) => {
    setOpenRaw((prev) => {
      const next = typeof v === "function" ? (v as (p: boolean) => boolean)(prev) : v;
      writeStoredBool(key, next);
      return next;
    });
  }, [key]);
  return [open, setOpen];
}

function readStoredBool(key: string, fallback = false) {''',
    "usePersistedOpen hook",
    guard='function usePersistedOpen(',
)

# --- 0b. Wire the 4 header-button components to persist their open state ---
for fn_sig, storage_key in [
    ('function NotificationBell() {\n  const { t } = usePanelLang();\n  const [open, setOpen] = useState(false);',
     'olc-modal-notifications-v1'),
    ('function ProjectUpdateButton({ disabled }: { disabled?: boolean }) {\n  const { t } = usePanelLang();\n  const [open, setOpen] = useState(false);',
     'olc-modal-project-v1'),
    ('function ComponentsDrawerButton() {\n  const { t } = usePanelLang();\n  const [open, setOpen] = useState(false);',
     'olc-modal-components-v1'),
    ('function ErrorsSummaryButton() {\n  const { t } = usePanelLang();\n  const [open, setOpen] = useState(false);',
     'olc-modal-errors-v1'),
]:
    repl(
        fn_sig,
        fn_sig.replace('const [open, setOpen] = useState(false);',
                       f'const [open, setOpen] = usePersistedOpen("{storage_key}");'),
        f"persist header button {storage_key}",
        guard=f'usePersistedOpen("{storage_key}")',
    )

# --- 1. App: pendingModal (lazy read) + restoredRef, right after showSettings ---
repl(
    '  const [showSettings, setShowSettings] = useState(false);',
    '''  const [showSettings, setShowSettings] = useState(false);
  const [pendingModal] = useState<string>(() => {
    try { return window.localStorage.getItem("olc-active-modal-v1") || ""; } catch { return ""; }
  });
  const modalRestoredRef = useRef(false);''',
    "App pendingModal state",
    guard='olc-active-modal-v1',
)

# --- 2. App: write + restore effects, after the mount data-load effect ---
mount_old = '''  useEffect(() => {
    if (!authenticated) return;
    Promise.all([loadState(), loadSettings(), loadMetrics(), loadAudit(), fetchInstanceDefaultsFromAPI()]).catch((err) =>
      setNotice(err.message),
    );
  }, [authenticated]);'''
mount_new = mount_old + '''

  // Persist which App-level modal is currently open (skip until restore ran).
  useEffect(() => {
    if (!modalRestoredRef.current) return;
    let d: any = null;
    if (showSettings) d = { k: "settings" };
    else if (createOpen) d = { k: "create" };
    else if (editClient) d = { k: "editClient", id: editClient.client_id };
    else if (createLocationClient) d = { k: "createLocation", id: createLocationClient.client_id };
    else if (editLocation) d = { k: "editLocation", id: editLocation.client.client_id, room: editLocation.location.room_id, idx: editLocation.index };
    else if (qrTarget) d = { k: "qr", id: qrTarget.clientID, room: qrTarget.location.room_id };
    else if (logTarget) d = { k: "instanceLogs", id: logTarget.clientID, room: logTarget.location.room_id };
    else if (clientLogTarget) d = { k: "clientLogs", id: clientLogTarget.client_id };
    try {
      if (d) window.localStorage.setItem("olc-active-modal-v1", JSON.stringify(d));
      else window.localStorage.removeItem("olc-active-modal-v1");
    } catch {
      /* ignore */
    }
  }, [showSettings, createOpen, editClient, createLocationClient, editLocation, qrTarget, logTarget, clientLogTarget]);

  // Restore the previously-open modal once client state is available after reload.
  useEffect(() => {
    if (!authenticated || modalRestoredRef.current || !state) return;
    modalRestoredRef.current = true;
    if (!pendingModal) return;
    let d: any;
    try { d = JSON.parse(pendingModal); } catch { return; }
    const cs = state.clients ?? [];
    const findClient = (id: string) => cs.find((c) => c.client_id === id);
    const findLoc = (c: any, room: string) => c?.locations?.find((l: any) => l.room_id === room);
    switch (d?.k) {
      case "settings": void openSettings(); break;
      case "create": openCreate(); break;
      case "editClient": { const c = findClient(d.id); if (c) openEdit(c); break; }
      case "createLocation": { const c = findClient(d.id); if (c) openCreateLocation(c); break; }
      case "editLocation": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (c && loc) openEditLocation(c, loc, d.idx); break; }
      case "qr": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) setQrTarget({ clientID: d.id, location: loc }); break; }
      case "instanceLogs": { const c = findClient(d.id); const loc = findLoc(c, d.room); if (loc) void openLogs(d.id, loc); break; }
      case "clientLogs": { const c = findClient(d.id); if (c) void openClientLogs(c); break; }
      default: break;
    }
  }, [authenticated, state, pendingModal]);'''
repl(mount_old, mount_new, "App write+restore effects", guard='modalRestoredRef.current = true;')

# --- 3. FeaturesPanel: persist + restore addon feature modals ---
fp_state_old = '''  const [logFeature, setLogFeature] = useState<FeatureName | null>(null);
  const [settingsFeature, setSettingsFeature] = useState<FeatureName | null>(null);

  const load = async () => {
    try {
      const res = await fetch("/api/features", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setData(await res.json());'''
fp_state_new = '''  const [logFeature, setLogFeature] = useState<FeatureName | null>(null);
  const [settingsFeature, setSettingsFeature] = useState<FeatureName | null>(null);
  const featureModalRestoredRef = useRef(false);

  useEffect(() => {
    if (logFeature) {
      try { window.localStorage.setItem("olc-active-feature-modal-v1", JSON.stringify({ k: "log", f: logFeature })); } catch { /* */ }
    } else if (settingsFeature) {
      try { window.localStorage.setItem("olc-active-feature-modal-v1", JSON.stringify({ k: "settings", f: settingsFeature })); } catch { /* */ }
    } else if (featureModalRestoredRef.current) {
      try { window.localStorage.removeItem("olc-active-feature-modal-v1"); } catch { /* */ }
    }
  }, [logFeature, settingsFeature]);

  const load = async () => {
    try {
      const res = await fetch("/api/features", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setData(await res.json());
      if (!featureModalRestoredRef.current) {
        featureModalRestoredRef.current = true;
        try {
          const raw = window.localStorage.getItem("olc-active-feature-modal-v1");
          if (raw) {
            const d = JSON.parse(raw);
            if (d?.k === "log" && d.f) setLogFeature(d.f as FeatureName);
            else if (d?.k === "settings" && d.f) setSettingsFeature(d.f as FeatureName);
          }
        } catch { /* */ }
      }'''
repl(fp_state_old, fp_state_new, "FeaturesPanel feature-modal memory", guard='olc-active-feature-modal-v1')

if changed:
    f.write_text(t)
print("[patch-modal-memory] ok")
PY
