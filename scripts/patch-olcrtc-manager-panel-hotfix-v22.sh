#!/usr/bin/env bash
# Hotfix v22: ошибки в модалке локации, автоген key, подсказки по провайдеру.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v22' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v22] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Provider hint under Room ID
old_room = '''      <label className="grid gap-2 text-sm text-muted-foreground">
        Room ID
        <RoomIDInput
          value={location.room_id}
          carrier={location.carrier}
          onChange={(room_id) => set({ room_id })}
        />
        <JitsiPreflightNotice carrier={location.carrier} roomID={location.room_id} />
      </label>'''

new_room = '''      <label className="grid gap-2 text-sm text-muted-foreground">
        Room ID
        <RoomIDInput
          value={location.room_id}
          carrier={location.carrier}
          onChange={(room_id) => set({ room_id })}
        />
        <p className="text-[11px] text-muted-foreground">
          {location.carrier === "jitsi"
            ? "Jitsi: полная ссылка meet (https://…) или домен/путь"
            : "Telemost / WB Stream / Jazz: только ID комнаты (цифры и латиница), без https://"}
        </p>
        <JitsiPreflightNotice carrier={location.carrier} roomID={location.room_id} />
      </label>'''

if old_room in t:
    t = t.replace(old_room, new_room, 1)

# locationModalError state
if "locationModalError" not in t:
    t = t.replace(
        "const [locationForm, setLocationForm] = useState<ClientLocationForm>(defaultLocationForm);",
        "const [locationForm, setLocationForm] = useState<ClientLocationForm>(defaultLocationForm);\n  const [locationModalError, setLocationModalError] = useState(\"\");",
        1,
    )

# addLocation with pre-check + auto key
old_add = '''  const addLocation = () =>
    runAction(async () => {
      if (!createLocationClient) return;
      assertLocationsValid([locationForm]);
      await request(`/api/clients/${encodeURIComponent(createLocationClient.client_id)}/locations`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          locations: locationsForSubmit([locationForm]),
        }),
      });
      setCreateLocationClient(null);
      setExpandedClients((current) => ({ ...current, [createLocationClient.client_id]: true }));
    }, "Локация создана");'''

new_add = '''  const addLocation = () => {
    if (!createLocationClient) return;
    const prepared = normalizeLocationForm({
      ...locationForm,
      key: locationForm.key.trim() || randomHex64(),
    });
    const roomErr = validateRoomIDInput(prepared.room_id, prepared.carrier);
    if (roomErr) {
      setLocationModalError(roomErr);
      return;
    }
    if (!prepared.name.trim()) {
      setLocationModalError("Укажите название локации");
      return;
    }
    setLocationModalError("");
    void runAction(async () => {
      await request(`/api/clients/${encodeURIComponent(createLocationClient.client_id)}/locations`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          locations: locationsForSubmit([prepared]),
        }),
      });
      setCreateLocationClient(null);
      setExpandedClients((current) => ({ ...current, [createLocationClient.client_id]: true }));
    }, "Локация создана");
  };'''

if old_add in t:
    t = t.replace(old_add, new_add, 1)

# addClient - auto key per location
old_client = '''      assertLocationsValid(createForm.locations);
      await request("/api/clients", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: createForm.client_id.trim(),
          refresh: cleanRefresh(createForm.refresh),
          quota: cleanQuota(createForm.quota),
          locations: locationsForSubmit(createForm.locations),
        }),
      });'''

new_client = '''      const locs = createForm.locations.map((loc) =>
        normalizeLocationForm({ ...loc, key: loc.key.trim() || randomHex64() }),
      );
      for (const loc of locs) {
        const re = validateRoomIDInput(loc.room_id, loc.carrier);
        if (re) throw new Error(re);
      }
      await request("/api/clients", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: createForm.client_id.trim(),
          refresh: cleanRefresh(createForm.refresh),
          quota: cleanQuota(createForm.quota),
          locations: locationsForSubmit(locs),
        }),
      });'''

if old_client in t:
    t = t.replace(old_client, new_client, 1)

# show error in create location modal
old_modal = '''        <Modal title={`Добавить локацию ${createLocationClient.client_id}`} onClose={() => setCreateLocationClient(null)}>
          <div className="p-5">
            <LocationFormFields location={locationForm} setLocation={setLocationForm} />'''

new_modal = '''        <Modal title={`Добавить локацию ${createLocationClient.client_id}`} onClose={() => { setCreateLocationClient(null); setLocationModalError(""); }}>
          <div className="p-5">
            {locationModalError ? <p className="mb-3 rounded border border-destructive/50 bg-destructive/10 p-2 text-sm text-destructive">{locationModalError}</p> : null}
            <LocationFormFields location={locationForm} setLocation={(loc) => { setLocationForm(loc); setLocationModalError(""); }} />'''

if old_modal in t:
    t = t.replace(old_modal, new_modal, 1)

# runAction: keep error visible when modal open — duplicate to modal if setLocationModalError exists
# (errors from API still go to notice)

if "/* olc-panel-hotfix-v22 */" not in t:
    if "/* olc-panel-hotfix-v21 */" in t:
        t = t.replace("/* olc-panel-hotfix-v21 */", "/* olc-panel-hotfix-v21 */\n/* olc-panel-hotfix-v22 */", 1)
    else:
        t = "/* olc-panel-hotfix-v22 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v22] ok")
PY
