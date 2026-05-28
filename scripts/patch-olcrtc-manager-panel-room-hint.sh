#!/usr/bin/env bash
# Inline validation hint under Room ID / Jitsi URL inputs.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'validateRoomIDInput' "$MAIN_TSX" && { echo "[patch-panel-room-hint] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helpers = r'''
function normalizeRoomIDInput(value: string): string {
  const roomID = value.trim();
  if (!roomID) return roomID;
  if (roomID.startsWith("http://") || roomID.startsWith("https://")) return roomID;
  if (roomID.startsWith("//")) return `https:${roomID}`;
  if (roomID.includes(".") && !roomID.includes(" ")) return `https://${roomID}`;
  return roomID;
}

/** Returns Russian error message or null if OK. */
function validateRoomIDInput(roomId: string, carrier: string): string | null {
  const rid = normalizeRoomIDInput(roomId);
  if (!rid) return "Укажите ссылку meet или room id";
  for (const ch of rid) {
    if (ch.charCodeAt(0) > 127) return "Некорректная ссылка: используйте латинский URL";
  }
  const c = (carrier || "jitsi").trim().toLowerCase();
  if (c === "jitsi" || c === "wbstream" || c === "telemost" || c === "jazz") {
    if (rid.startsWith("http://") || rid.startsWith("https://")) {
      try {
        new URL(rid);
        return null;
      } catch {
        return "Некорректная ссылка";
      }
    }
    if (rid.includes(".") && !rid.includes(" ")) return null;
    return "Некорректная ссылка: https://meet.example.com/room или meet.example.com/room";
  }
  return null;
}

function validateClientIDInput(id: string): string | null {
  const v = id.trim();
  if (!v) return "Укажите ID клиента";
  if (v.length > 64) return "ID не длиннее 64 символов";
  if (!/^[a-zA-Z0-9_-]+$/.test(v)) return "ID: только латиница, цифры, _ и -";
  return null;
}

function assertLocationsValid(locations: ClientLocationForm[]) {
  for (const loc of locations) {
    const err = validateRoomIDInput(loc.room_id, loc.carrier);
    if (err) throw new Error(err);
  }
}

function RoomIDInput({
  value,
  carrier,
  onChange,
  inputClassName = "h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary",
}: {
  value: string;
  carrier: string;
  onChange: (value: string) => void;
  inputClassName?: string;
}) {
  const err = value.trim() ? validateRoomIDInput(value, carrier) : null;
  return (
    <div className="grid gap-1">
      <input
        className={`${inputClassName}${err ? " border-destructive/70 focus:border-destructive" : ""}`}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={roomPlaceholder(carrier)}
      />
      {err ? <p className="text-xs text-destructive">{err}</p> : null}
    </div>
  );
}

'''

anchor = "function roomPlaceholder(carrier: string)"
t = t.replace(anchor, helpers + "\n" + anchor, 1)

# LocationFormFields — single room input
old_loc = """      <label className="grid gap-2 text-sm text-muted-foreground">
        Room ID
        <input
          className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
          value={location.room_id}
          onChange={(event) => set({ room_id: event.target.value })}
          placeholder={roomPlaceholder(location.carrier)}
        />
      </label>"""

new_loc = """      <label className="grid gap-2 text-sm text-muted-foreground">
        Room ID
        <RoomIDInput
          value={location.room_id}
          carrier={location.carrier}
          onChange={(room_id) => set({ room_id })}
        />
      </label>"""

if old_loc in t:
    t = t.replace(old_loc, new_loc, 1)

# ClientFormFields — per-location room input
old_multi = """            <label className="grid gap-2 text-sm text-muted-foreground">
              Room ID
              <input
                className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                value={location.room_id}
                onChange={(event) => setLocation(index, { room_id: event.target.value })}
                placeholder={roomPlaceholder(location.carrier)}
              />
            </label>"""

new_multi = """            <label className="grid gap-2 text-sm text-muted-foreground">
              Room ID
              <RoomIDInput
                value={location.room_id}
                carrier={location.carrier}
                onChange={(room_id) => setLocation(index, { room_id })}
                inputClassName="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
              />
            </label>"""

if old_multi in t:
    t = t.replace(old_multi, new_multi, 1)

# locationsForSubmit — normalize room_id
t = t.replace(
    "    room_id: location.room_id.trim(),",
    "    room_id: normalizeRoomIDInput(location.room_id),",
    1,
)

# add assertLocationsValid to submit paths
t = t.replace(
    '      if (!createForm.client_id.trim()) throw new Error("Укажи ID клиента");',
    """      const cidErr = validateClientIDInput(createForm.client_id);
      if (cidErr) throw new Error(cidErr);
      assertLocationsValid(createForm.locations);""",
    1,
)

t = t.replace(
    "      if (!createLocationClient) return;\n      await request",
    "      if (!createLocationClient) return;\n      assertLocationsValid([locationForm]);\n      await request",
    1,
)

t = t.replace(
    "      if (!editLocation) return;\n      const nextLocations",
    "      if (!editLocation) return;\n      assertLocationsValid([locationForm]);\n      const nextLocations",
    1,
)

p.write_text(t)
print("[patch-panel-room-hint] ok"); print(0); raise SystemExit(0)
PY
