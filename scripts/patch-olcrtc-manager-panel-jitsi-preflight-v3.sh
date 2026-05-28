#!/usr/bin/env bash
# UI v3: show explicit Bridge WS post-join compatibility block.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-jitsi-preflight-ui-v3' "$MAIN_TSX" && { echo "[patch-panel-jitsi-preflight-v3] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "bridge_postjoin_risk?: boolean;" not in t:
    t = t.replace(
        "  bosh_url?: string;\n};",
        "  bosh_url?: string;\n  bridge_postjoin_risk?: boolean;\n  bridge_postjoin_note?: string;\n};",
        1,
    )

needle = """          {result.details?.slice(0, 2).map((d) => (
            <p key={d} className="text-muted-foreground">
              - {d}
            </p>
          ))}
        </div>
      ) : (
"""
insert = """          {result.details?.slice(0, 3).map((d) => (
            <p key={d} className="text-muted-foreground">
              - {d}
            </p>
          ))}
          <div className="mt-2 rounded border border-border/70 bg-background/40 px-2 py-2">
            <p className="text-[11px] uppercase text-muted-foreground">Bridge WS compatibility (post-join pattern)</p>
            <p className={result.bridge_postjoin_risk ? "mt-1 text-amber-300" : "mt-1 text-emerald-400"}>
              {result.bridge_postjoin_risk
                ? "join может пройти, но bridge websocket может быть несовместим"
                : "явных признаков bridge websocket-конфликта не обнаружено"}
            </p>
            <p className="mt-1 text-muted-foreground">
              OK-паттерн: "jitsi: bridge open ..." + "Link connected"
            </p>
            <p className="text-muted-foreground">
              Fail-паттерн: "expected handshake response status code 101 but got 200"
            </p>
            {result.bridge_postjoin_note ? (
              <p className="mt-1 text-muted-foreground">Подсказка: {result.bridge_postjoin_note}</p>
            ) : null}
          </div>
        </div>
      ) : (
"""
if needle in t and "Bridge WS compatibility (post-join pattern)" not in t:
    t = t.replace(needle, insert, 1)

if "olc-jitsi-preflight-ui-v3" not in t:
    t = t.replace("/* olc-jitsi-preflight-ui-v2 */", "/* olc-jitsi-preflight-ui-v2 */\n/* olc-jitsi-preflight-ui-v3 */", 1)

p.write_text(t)
print("[patch-panel-jitsi-preflight-v3] ok"); print(0); raise SystemExit(0)
PY
