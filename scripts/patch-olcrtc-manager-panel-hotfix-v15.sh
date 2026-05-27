#!/usr/bin/env bash
# Hotfix v15: feature logs API errors as text; clear stuck component job UI on stale failed.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v15' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v15] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old_fetch = """        const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
        const body = (await res.json()) as { lines?: string[]; path?: string };
        if (!cancelled) {
          setLines(body.lines ?? []);
          setPath(body.path ?? "");
        }"""

new_fetch = """        const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
        const raw = await res.text();
        let body: { lines?: string[]; path?: string; error?: string } = {};
        try {
          body = (raw ? JSON.parse(raw) : {}) as { lines?: string[]; path?: string; error?: string };
        } catch {
          body = { lines: [raw || `HTTP ${res.status}`] };
        }
        if (!res.ok) {
          body = { lines: [body.error || raw || `HTTP ${res.status}`] };
        }
        if (!cancelled) {
          setLines(body.lines ?? []);
          setPath(body.path ?? "");
        }"""

if old_fetch in t:
    t = t.replace(old_fetch, new_fetch, 1)

old_btn = """                  const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
                  const body = (await res.json()) as { lines?: string[]; path?: string };
                  setLines(body.lines ?? []);
                  setPath(body.path ?? "");"""

new_btn = """                  const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
                  const raw = await res.text();
                  let body: { lines?: string[]; path?: string; error?: string } = {};
                  try {
                    body = (raw ? JSON.parse(raw) : {}) as { lines?: string[]; path?: string; error?: string };
                  } catch {
                    body = { lines: [raw || `HTTP ${res.status}`] };
                  }
                  if (!res.ok) body = { lines: [body.error || raw || `HTTP ${res.status}`] };
                  setLines(body.lines ?? []);
                  setPath(body.path ?? "");"""

if old_btn in t:
    t = t.replace(old_btn, new_btn, 1)

if "olc-panel-hotfix-v15" not in t:
    if "/* olc-panel-hotfix-v13 */" in t:
        t = t.replace("/* olc-panel-hotfix-v13 */", "/* olc-panel-hotfix-v13 */\n/* olc-panel-hotfix-v15 */", 1)
    else:
        t = "/* olc-panel-hotfix-v15 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v15] ok")
PY
