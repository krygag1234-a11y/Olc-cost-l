#!/usr/bin/env bash
# Hotfix v24: componentInstalled("warp") — убрать ошибочно вставленный save WARP settings (body/return err).
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v24' "$MAIN_GO" && { echo "[patch-manager-hotfix-v24] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

broken = re.compile(
    r'\tcase "warp":\n\t\tif v, ok := body\["proxy"\]\.\(string\); ok \{[\s\S]*?\n\t\treturn nil\n',
)
fixed = '\tcase "warp":\n\t\t_, err := exec.LookPath("warp-cli")\n\t\treturn err == nil\n'

if 'body["proxy"]' in t.split('func componentInstalled')[1].split('func loadFeatureFlagsMap')[0]:
    t2, n = broken.subn(fixed, t, count=1)
    if n:
        t = t2
        print("[patch-manager-hotfix-v24] componentInstalled warp fixed")
    else:
        print("[patch-manager-hotfix-v24] pattern not found", file=sys.stderr)
        sys.exit(1)
else:
    print("[patch-manager-hotfix-v24] already ok (skip)")

if "olc-manager-hotfix-v24" not in t:
    t = "/* olc-manager-hotfix-v24 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v24] ok")
PY
