#!/usr/bin/env bash
set -euo pipefail

repo=${1:?usage: $0 <manager-repo-root>}
go_mod="$repo/go.mod"
[[ -f "$go_mod" ]] || { echo "[patch-manager-go-version] missing $go_mod" >&2; exit 1; }

python3 - "$go_mod" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
updated, count = re.subn(r'(?m)^go\s+\d+\.\d+(?:\.\d+)?\s*$', 'go 1.26.3', text, count=1)
if count != 1:
    raise SystemExit('[patch-manager-go-version] go directive not found')
if not re.search(r'(?m)^go 1\.26\.3$', updated):
    raise SystemExit('[patch-manager-go-version] failed to set go 1.26.3')
path.write_text(updated)
PY

echo "[patch-manager-go-version] go.mod -> go 1.26.3"
