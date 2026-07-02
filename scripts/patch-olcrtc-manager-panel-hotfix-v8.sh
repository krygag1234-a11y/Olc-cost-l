#!/usr/bin/env bash
# Hotfix v8: define componentJobUiVisible when TTL patch left calls but dropped helpers.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "function componentJobUiVisible" in t:
    print("[patch-panel-hotfix-v8] componentJobUiVisible already defined"); raise SystemExit(0)
    sys.exit(0)

if "componentJobUiVisible" not in t:
    print("[patch-panel-hotfix-v8] skip: no usages"); raise SystemExit(0)
    sys.exit(0)

if "const COMPONENT_JOB_UI_TTL_MS" in t:
    print("[patch-panel-hotfix-v8] COMPONENT_JOB_UI_TTL_MS already defined, skip"); raise SystemExit(0)

const_block = '''
const COMPONENT_JOB_UI_TTL_MS = 120_000;

function componentJobFinishedMs(j?: { finished_at?: string; status?: string }): number | null {
  if (!j?.finished_at) return null;
  const ms = Date.parse(j.finished_at);
  return Number.isFinite(ms) ? ms : null;
}

function componentJobUiVisible(j?: { status?: string; finished_at?: string }): boolean {
  if (!j?.status) return false;
  if (j.status === "running") return true;
  if (j.status === "failed") {
    const doneAt = componentJobFinishedMs(j);
    return doneAt == null || Date.now() - doneAt < COMPONENT_JOB_UI_TTL_MS * 2;
  }
  if (j.status === "done") {
    const doneAt = componentJobFinishedMs(j);
    return doneAt == null || Date.now() - doneAt < COMPONENT_JOB_UI_TTL_MS;
  }
  return false;
}

'''

anchor = "const COMPONENT_DRAWER_ITEMS = ["
if anchor not in t:
    print("[patch-panel-hotfix-v8] failed: no COMPONENT_DRAWER_ITEMS anchor", file=sys.stderr); raise SystemExit(0)
    sys.exit(1)

t = t.replace(anchor, const_block + anchor, 1)

if "olc-panel-hotfix-v8" not in t:
    if "/* olc-panel-hotfix-v7 */" in t:
        t = t.replace("/* olc-panel-hotfix-v7 */", "/* olc-panel-hotfix-v7 */\n/* olc-panel-hotfix-v8 */", 1)
    else:
        t = "/* olc-panel-hotfix-v8 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v8] ok"); raise SystemExit(0)
PY
