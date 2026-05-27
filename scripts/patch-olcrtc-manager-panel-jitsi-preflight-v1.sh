#!/usr/bin/env bash
# Add Jitsi preflight hint/check in location form.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-jitsi-preflight-ui-v1' "$MAIN_TSX" && { echo "[patch-panel-jitsi-preflight-v1] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

marker = "/* olc-jitsi-preflight-ui-v1 */"
if marker not in t:
    t = t.replace('import React, {', marker + '\nimport React, {', 1)

insert_after = """function RoomIDInput({
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
"""

addon = """
type JitsiPreflightResult = {
  ok?: boolean;
  code?: string;
  summary?: string;
  details?: string[];
  ws_status?: number;
  ws_url?: string;
  bosh_status?: number;
  bosh_url?: string;
};

function JitsiPreflightNotice({ carrier, roomID }: { carrier: string; roomID: string }) {
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<JitsiPreflightResult | null>(null);
  const [error, setError] = useState("");
  const normalized = normalizeRoomIDInput(roomID);
  const canCheck = (carrier || "").toLowerCase() === "jitsi" && Boolean(normalized);
  const roomErr = canCheck ? validateRoomIDInput(normalized, "jitsi") : null;

  const runCheck = useCallback(async () => {
    if (!canCheck || roomErr) return;
    setBusy(true);
    setError("");
    try {
      const q = encodeURIComponent(normalized);
      const res = await request(`/api/jitsi/preflight?room_id=${q}`, { cache: "no-store" });
      setResult((await res.json()) as JitsiPreflightResult);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }, [canCheck, roomErr, normalized]);

  useEffect(() => {
    if (!canCheck || roomErr) {
      setResult(null);
      setError("");
      return;
    }
    const id = window.setTimeout(() => void runCheck(), 700);
    return () => window.clearTimeout(id);
  }, [canCheck, roomErr, runCheck]);

  if ((carrier || "").toLowerCase() !== "jitsi") return null;
  return (
    <div className="mt-2 rounded-md border border-border/80 bg-muted/20 px-3 py-2 text-xs">
      <div className="flex items-center justify-between gap-2">
        <span className="text-muted-foreground">Jitsi preflight</span>
        <button
          type="button"
          className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 hover:bg-accent disabled:opacity-50"
          disabled={!canCheck || Boolean(roomErr) || busy}
          onClick={() => void runCheck()}
        >
          {busy ? "Проверка…" : "Проверить"}
        </button>
      </div>
      {roomErr ? (
        <p className="mt-1 text-destructive">{roomErr}</p>
      ) : error ? (
        <p className="mt-1 text-destructive">Ошибка проверки: {error}</p>
      ) : result ? (
        <div className="mt-1 space-y-1">
          <p className={result.ok ? "text-emerald-400" : "text-amber-300"}>
            {result.summary || "Проверка завершена"}
          </p>
          <p className="text-muted-foreground">
            ws: {result.ws_status ?? "?"} {result.ws_url ? `(${result.ws_url})` : ""}
          </p>
          {result.details?.slice(0, 2).map((d) => (
            <p key={d} className="text-muted-foreground">
              - {d}
            </p>
          ))}
        </div>
      ) : (
        <p className="mt-1 text-muted-foreground">Проверка запускается автоматически при вводе room URL.</p>
      )}
    </div>
  );
}
"""

if "function JitsiPreflightNotice(" not in t and insert_after in t:
    t = t.replace(insert_after, insert_after + addon, 1)

old_loc = """      <label className="grid gap-2 text-sm text-muted-foreground">
        Room ID
        <RoomIDInput
          value={location.room_id}
          carrier={location.carrier}
          onChange={(room_id) => set({ room_id })}
        />
      </label>
"""
new_loc = """      <label className="grid gap-2 text-sm text-muted-foreground">
        Room ID
        <RoomIDInput
          value={location.room_id}
          carrier={location.carrier}
          onChange={(room_id) => set({ room_id })}
        />
        <JitsiPreflightNotice carrier={location.carrier} roomID={location.room_id} />
      </label>
"""
if old_loc in t and "JitsiPreflightNotice carrier={location.carrier}" not in t:
    t = t.replace(old_loc, new_loc, 1)

p.write_text(t)
print("[patch-panel-jitsi-preflight-v1] ok")
PY

