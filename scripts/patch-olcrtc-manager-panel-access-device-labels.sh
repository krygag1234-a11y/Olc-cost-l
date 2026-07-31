#!/usr/bin/env bash
set -euo pipefail

tsx=${1:?usage: $0 <main.tsx>}

python3 - "$tsx" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

def one(old: str, new: str, label: str) -> None:
    global text
    if old in text:
        if text.count(old) != 1:
            raise SystemExit(f"{label}: anchor is not unique ({text.count(old)})")
        text = text.replace(old, new, 1)
    elif new not in text:
        raise SystemExit(f"{label}: anchor not found")

# Global connection allowlist: match the already editable subscription list.
one(
    'const setConnDevice = (hwid: string, patch: { enabled?: boolean }) =>',
    'const setConnDevice = (hwid: string, patch: { enabled?: boolean; label?: string }) =>',
    'global connection label setter',
)
one(
    '''                      <input type="checkbox" title="Вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => setConnDevice(d.hwid, { enabled: e.target.checked })} />
                      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>''',
    '''                      <input type="checkbox" title="Вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => setConnDevice(d.hwid, { enabled: e.target.checked })} />
                      <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
                        placeholder="имя" defaultValue={d.label || ""}
                        onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) setConnDevice(d.hwid, { label: e.target.value }); }} />
                      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>''',
    'global connection label input',
)

# Per-client subscription/connection allowlists: add the same editable field.
one(
    'const devRow = (d: Dev, onToggle: ((en: boolean) => void) | null, onRemove: () => void, extra?: any) => (',
    'const devRow = (d: Dev, onToggle: ((en: boolean) => void) | null, onRemove: () => void, extra?: any, onLabel?: (label: string) => void) => (',
    'per-client device row signature',
)
one(
    '''      {onToggle && <input type="checkbox" title="вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => onToggle(e.target.checked)} />}
      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.label ? d.label + " · " : ""}{d.hwid}</span>''',
    '''      {onToggle && <input type="checkbox" title="вкл/выкл" checked={d.enabled !== false} disabled={busy} onChange={(e) => onToggle(e.target.checked)} />}
      {onLabel && <input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
        placeholder="имя" defaultValue={d.label || ""}
        onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) onLabel(e.target.value); }} />}
      <span className={`min-w-0 flex-1 truncate font-mono ${d.enabled === false ? "text-muted-foreground line-through" : ""}`}>{d.hwid}</span>''',
    'per-client label input',
)
one(
    '''{allow.map((d) => devRow(d, (en) => toggleAllow(d.hwid, en), () => rmAllow(d.hwid), crossBtn(d.hwid, "allow", "conn", connAllow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnAllow(d.hwid))))}''',
    '''{allow.map((d) => devRow(d, (en) => toggleAllow(d.hwid, en), () => rmAllow(d.hwid), crossBtn(d.hwid, "allow", "conn", connAllow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addConnAllow(d.hwid)), (label) => void save({ allow: allow.map((x) => x.hwid === d.hwid ? { ...x, label } : x) })))}''',
    'per-client subscription label save',
)
one(
    '''{connAllow.map((d) => devRow(d, (en) => toggleConnAllow(d.hwid, en), () => rmConnAllow(d.hwid), crossBtn(d.hwid, "allow", "sub", allow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addAllow(d.hwid))))}''',
    '''{connAllow.map((d) => devRow(d, (en) => toggleConnAllow(d.hwid, en), () => rmConnAllow(d.hwid), crossBtn(d.hwid, "allow", "sub", allow.some((x) => x.hwid.toLowerCase() === d.hwid.toLowerCase()), () => addAllow(d.hwid)), (label) => void save({ conn_allow: connAllow.map((x) => x.hwid === d.hwid ? { ...x, label } : x) })))}''',
    'per-client connection label save',
)

# Attempt logs display a configured name, with the stable HWID retained in a
# title and a secondary monospace line for audit/debugging.
attempt_known = {
    'const known = isKnown(hwid);': 'const known = isKnown(hwid);\n                  const knownDev = devices.find((d) => d.hwid.toLowerCase() === hwid.toLowerCase());',
    'const known = allow.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase() && d.enabled !== false);': 'const known = allow.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase() && d.enabled !== false);\n                const knownDev = allow.find((d) => d.hwid.toLowerCase() === hwid.toLowerCase());',
}
for old, new in attempt_known.items():
    one(old, new, 'subscription log label lookup')

old_attempt = '{hwid || "(без hwid)"}'
new_attempt = '{knownDev?.label?.trim() || hwid || "(без hwid)"}{knownDev?.label?.trim() && <span className="ml-1 text-[10px] text-muted-foreground" title={hwid}>({hwid})</span>}'
if old_attempt in text:
    if text.count(old_attempt) != 2:
        raise SystemExit(f"expected 2 subscription log displays, got {text.count(old_attempt)}")
    text = text.replace(old_attempt, new_attempt)
elif text.count(new_attempt) != 2:
    raise SystemExit('subscription log label displays not found')

conn_known = {
    'const known = connDevices.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);': 'const known = connDevices.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);\n                  const knownDev = connDevices.find((d) => d.hwid.toLowerCase() === dev.toLowerCase());',
    'const known = connAllow.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);': 'const known = connAllow.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);\n                const knownDev = connAllow.find((d) => d.hwid.toLowerCase() === dev.toLowerCase());',
}
for old, new in conn_known.items():
    one(old, new, 'connection log label lookup')

old_conn = '{dev || "—"}'
new_conn = '{knownDev?.label?.trim() || dev || "—"}{knownDev?.label?.trim() && <span className="ml-1 text-[10px] text-muted-foreground" title={dev}>({dev})</span>}'
if old_conn in text:
    if text.count(old_conn) != 2:
        raise SystemExit(f"expected 2 connection log displays, got {text.count(old_conn)}")
    text = text.replace(old_conn, new_conn)
elif text.count(new_conn) != 2:
    raise SystemExit('connection log label displays not found')

path.write_text(text)
PY

echo "patched device labels in all access allowlists and logs"
