#!/usr/bin/env bash
# Keep CRUD forms explicitly saved while making instance defaults truly autosaved.
set -euo pipefail

target="${1:-/tmp/olcrtc-manager-panel/src/main.tsx}"
[[ -f "$target" ]] || { echo "[defaults-autosave-crud] target not found: $target" >&2; exit 1; }

python3 - "$target" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "OLC_DEFAULTS_AUTOSAVE_CRUD_V1"
if marker in text:
    print(f"[defaults-autosave-crud] already applied: {path}")
    raise SystemExit(0)

def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"[defaults-autosave-crud] {label}: expected one match, got {count}")
    return source.replace(old, new, 1)

# Convert every server location to the complete edit-form shape. After the
# Jitsi Server/Room split, raw sibling locations do not have jitsi_instance;
# passing them directly to locationsForSubmit crashes before the PUT request.
normalize_anchor = """}

function normalizeForm(form: ClientForm): ClientForm {"""
state_converter = r''' }

function locationStateForEdit(location: LocationState): ClientLocationForm {
  const raw = location as LocationState & { proxy?: Partial<Socks5Proxy> & { port?: string | number } };
  return normalizeLocationForm({
    name: location.name,
    room_id: location.room_id,
    jitsi_instance: DEFAULT_JITSI_INSTANCE,
    key: location.key,
    carrier: location.carrier,
    transport: location.transport,
    payload: location.payload ?? {},
    dns: location.dns,
    proxy: proxyFromState(raw.proxy),
    link: location.link,
  });
}

function normalizeForm(form: ClientForm): ClientForm {'''
text = replace_once(text, normalize_anchor, state_converter, "location state converter")

open_edit_pattern = re.compile(
    r'''    setLocationForm\(\n      normalizeLocationForm\(\{\n.*?\n      \}\),\n    \);''',
    re.S,
)
open_edit_start = text.find("  const openEditLocation = (")
open_edit_end = text.find("  const addClient = ", open_edit_start)
if open_edit_start < 0 or open_edit_end < 0:
    raise SystemExit("[defaults-autosave-crud] openEditLocation bounds changed")
open_edit = text[open_edit_start:open_edit_end]
open_edit, count = open_edit_pattern.subn("    setLocationForm(locationStateForEdit(location));", open_edit, count=1)
if count != 1:
    raise SystemExit(f"[defaults-autosave-crud] openEditLocation form: expected one match, got {count}")
text = text[:open_edit_start] + open_edit + text[open_edit_end:]

new_siblings = r'''      const nextLocations = editLocation.client.locations.map((location, index) =>
        index === editLocation.index
          ? normalizeLocationForm(locationForm)
          : locationStateForEdit(location),
      );'''
update_start = text.find("  const updateLocation = () =>")
update_end = text.find("  const deleteClient = ", update_start)
if update_start < 0 or update_end < 0:
    raise SystemExit("[defaults-autosave-crud] updateLocation bounds changed")
update_block = text[update_start:update_end]
update_block, count = re.subn(
    r'''      const nextLocations = editLocation\.client\.locations\.map\(\(location, index\) =>\n.*?\n      \);''',
    new_siblings,
    update_block,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f"[defaults-autosave-crud] normalize edit siblings: expected one match, got {count}")
text = text[:update_start] + update_block + text[update_end:]
text = replace_once(
    text,
    "      if (!editLocation) return;\n      assertLocationsValid([locationForm]);",
    "      if (!editLocation) return;\n      setLocationModalError(\"\");\n      assertLocationsValid([normalizeLocationForm(locationForm)]);",
    "clear edit error and validate normalized form",
)

# runAction used to put errors only into the page notice hidden behind a modal.
app_start = text.find("function App() {")
open_create_start = text.find("  const openCreate = () =>", app_start)
if app_start < 0 or open_create_start < 0:
    raise SystemExit("[defaults-autosave-crud] App/runAction bounds changed")
app_prefix = text[app_start:open_create_start]
app_prefix = replace_once(
    app_prefix,
    '''    } catch (err) {
      setNotice(err instanceof Error ? err.message : String(err));
    } finally {''',
    '''    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setNotice(message);
      if (editLocation || createLocationClient) setLocationModalError(message);
    } finally {''',
    "modal-visible CRUD error",
)
text = text[:app_start] + app_prefix + text[open_create_start:]

edit_modal_start = text.find("      {editLocation && (")
edit_modal_end = text.find("      {instanceInfoTarget && (", edit_modal_start)
if edit_modal_start < 0 or edit_modal_end < 0:
    raise SystemExit("[defaults-autosave-crud] edit modal bounds changed")
edit_modal = text[edit_modal_start:edit_modal_end]
edit_modal = replace_once(
    edit_modal,
    'onClose={() => setEditLocation(null)}',
    'onClose={() => { setEditLocation(null); setLocationModalError(""); }}',
    "edit modal close",
)
edit_modal = replace_once(
    edit_modal,
    '''          <div className="p-5">
            <LocationFormFields''',
    '''          <div className="p-5">
            {locationModalError ? <p className="mb-3 rounded border border-destructive/50 bg-destructive/10 p-2 text-sm text-destructive">{locationModalError}</p> : null}
            <LocationFormFields''',
    "edit modal error message",
)
edit_modal = replace_once(
    edit_modal,
    "              setLocation={setLocationForm}",
    '              setLocation={(next) => { setLocationForm(next); setLocationModalError(""); }}',
    "edit modal clear error on change",
)
edit_modal = replace_once(
    edit_modal,
    'onClick={() => setEditLocation(null)}',
    'onClick={() => { setEditLocation(null); setLocationModalError(""); }}',
    "edit modal cancel",
)
text = text[:edit_modal_start] + edit_modal + text[edit_modal_end:]

# Work only inside InstanceDefaultsModal so no other reviewed controls move.
defaults_start = text.find("function InstanceDefaultsModal(")
defaults_end = text.find("async function request(", defaults_start)
if defaults_start < 0 or defaults_end < 0:
    raise SystemExit("[defaults-autosave-crud] defaults modal bounds changed")
defaults = text[defaults_start:defaults_end]

old_header = r'''  const [cfg, setCfg] = useState<InstanceDefaultsV1>(() => loadInstanceDefaults());
  const [saved, setSaved] = useState("");
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let cancelled = false;
    void fetchInstanceDefaultsFromAPI().then((next) => {
      if (!cancelled) {
        setCfg(next);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);'''
new_header = r'''  const [cfg, setCfg] = useState<InstanceDefaultsV1>(() => loadInstanceDefaults());
  const [saved, setSaved] = useState("");
  const [loading, setLoading] = useState(true);
  const cfgRef = useRef(cfg);
  const savedSnapshotRef = useRef("");
  const autoSaveTimerRef = useRef<number | null>(null);
  const saveQueueRef = useRef<Promise<void>>(Promise.resolve());

  const persistInstanceDefaults = useCallback((next: InstanceDefaultsV1) => {
    const snapshot = JSON.stringify(next);
    if (snapshot === savedSnapshotRef.current) return saveQueueRef.current;
    setSaved("Сохраняю…");
    const run = async () => {
      try {
        await saveInstanceDefaults(next);
        savedSnapshotRef.current = snapshot;
        setSaved("Сохранено автоматически");
      } catch (error) {
        setSaved(`Ошибка автосохранения: ${error instanceof Error ? error.message : String(error)}`);
      }
    };
    saveQueueRef.current = saveQueueRef.current.then(run, run);
    return saveQueueRef.current;
  }, []);

  const flushInstanceDefaults = useCallback(() => {
    if (autoSaveTimerRef.current !== null) {
      window.clearTimeout(autoSaveTimerRef.current);
      autoSaveTimerRef.current = null;
    }
    if (!loading) void persistInstanceDefaults(cfgRef.current);
  }, [loading, persistInstanceDefaults]);

  const closeInstanceDefaults = () => {
    flushInstanceDefaults();
    onClose();
  };
  const backFromInstanceDefaults = () => {
    flushInstanceDefaults();
    onBack();
  };

  useEffect(() => {
    let cancelled = false;
    void fetchInstanceDefaultsFromAPI().then((next) => {
      if (!cancelled) {
        cfgRef.current = next;
        savedSnapshotRef.current = JSON.stringify(next);
        setCfg(next);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    cfgRef.current = cfg;
    if (loading || JSON.stringify(cfg) === savedSnapshotRef.current) return;
    if (autoSaveTimerRef.current !== null) window.clearTimeout(autoSaveTimerRef.current);
    setSaved("Ожидает автосохранения…");
    autoSaveTimerRef.current = window.setTimeout(() => {
      autoSaveTimerRef.current = null;
      void persistInstanceDefaults(cfgRef.current);
    }, 650);
    return () => {
      if (autoSaveTimerRef.current !== null) window.clearTimeout(autoSaveTimerRef.current);
    };
  }, [cfg, loading, persistInstanceDefaults]);'''
header_start = defaults.find("  const [cfg, setCfg] = useState<InstanceDefaultsV1>")
header_end = defaults.find("  const setGlobalPort = ", header_start)
if header_start < 0 or header_end < 0:
    raise SystemExit("[defaults-autosave-crud] defaults autosave hook bounds changed")
defaults = defaults[:header_start] + new_header + "\n\n" + defaults[header_end:]
defaults = replace_once(
    defaults,
    '<Modal title="Настройки инстансов по умолчанию" onClose={onClose}>',
    '<Modal title="Настройки инстансов по умолчанию" onClose={closeInstanceDefaults}>',
    "defaults close flush",
)
defaults = replace_once(
    defaults,
    'onClick={onBack}>\n          ← Назад к настройкам OlcRTC',
    'onClick={backFromInstanceDefaults}>\n          ← Назад к настройкам OlcRTC',
    "top back flush",
)

toggle_pattern = re.compile(
    r'''        <div className="mt-2 flex items-center gap-2 text-xs">\n(?P<button>\s*<OlcToggleButton.*?/>\n)\s*Это максимальные значения\? \(нельзя выставить выше при создании\)\n        </div>''',
    re.S,
)
defaults, count = toggle_pattern.subn(
    r'''        <div className="mt-2 flex items-center justify-between gap-3 text-xs">
          <span>Это максимальные значения? (нельзя выставить выше при создании)</span>
\g<button>        </div>''',
    defaults,
    count=1,
)
if count != 1:
    raise SystemExit(f"[defaults-autosave-crud] defaults toggle layout: expected one match, got {count}")

old_footer = r'''        {saved && <p className="text-xs text-emerald-400">{saved}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" className="rounded border border-border px-3 py-1 text-xs hover:bg-muted" onClick={onBack}>
            Назад
          </button>
          <button
            type="button"
            className="rounded border border-primary bg-primary/20 px-3 py-1 text-xs text-primary disabled:opacity-60"
            disabled={loading}
            onClick={() => {
              void (async () => {
                try {
                  await saveInstanceDefaults(cfg);
                  setSaved("Сохранено на сервере (применяется к новым инстансам)");
                } catch (e) {
                  setSaved(e instanceof Error ? e.message : String(e));
                }
              })();
            }}
          >
            Сохранить
          </button>
        </div>'''
new_footer = r'''        <p className={`text-xs ${saved.startsWith("Ошибка") ? "text-destructive" : "text-muted-foreground"}`}>
          {saved || "Изменения сохраняются автоматически"}
        </p>'''
defaults = replace_once(defaults, old_footer, new_footer, "remove defaults footer buttons")

text = text[:defaults_start] + defaults + text[defaults_end:]
text += f"\n// {marker}\n"
path.write_text(text)
print(f"[defaults-autosave-crud] applied: {path}")
PY
