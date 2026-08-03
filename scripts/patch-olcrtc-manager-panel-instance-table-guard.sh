#!/usr/bin/env bash
# Keep long instance names from squeezing or wrapping the location action bar.
set -euo pipefail

target="${1:-/tmp/olcrtc-manager-panel/src/main.tsx}"
[[ -f "$target" ]] || { echo "[instance-table-guard] target not found: $target" >&2; exit 1; }

python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "OLC_INSTANCE_TABLE_GUARD_V1"
if marker in text:
    print(f"[instance-table-guard] already applied: {path}")
    raise SystemExit(0)

def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"[instance-table-guard] {label}: expected one match, got {count}")
    text = text.replace(old, new, 1)

replace_once(
    '<table className="w-full min-w-[920px] border-collapse text-sm">',
    '<table className="w-full min-w-[1160px] border-collapse text-sm">',
    "stable table width",
)
replace_once(
    '<th className="py-2 pr-3 font-medium">Локация</th>',
    '<th className="w-[150px] max-w-[150px] py-2 pr-3 font-medium">Локация</th>',
    "location header width",
)
replace_once(
    '<td className="py-3 pr-3 font-medium">{loc.name || "Default"}</td>',
    '''<td className="w-[150px] max-w-[150px] py-3 pr-3 font-medium">
                                  <span className="block max-w-[150px] truncate" title={loc.name || "Default"}>
                                    {loc.name || "Default"}
                                  </span>
                                </td>''',
    "truncate long location name",
)
replace_once(
    '<td className="py-3 text-right">\n                                  <div className="flex flex-wrap justify-end gap-2">',
    '<td className="w-px whitespace-nowrap py-3 text-right">\n                                  <div className="flex flex-nowrap justify-end gap-2">',
    "non-wrapping location actions",
)

text += f"\n// {marker}\n"
path.write_text(text)
print(f"[instance-table-guard] applied: {path}")
PY
