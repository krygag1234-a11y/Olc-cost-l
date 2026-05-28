#!/usr/bin/env bash
# Hotfix v7: restore collapse button in "Сеть и обход" and remove misplaced button in client form.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

stray_btn = """        <button type="button" className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs hover:bg-muted" onClick={() => setCollapsed((v) => !v)}>
          {collapsed ? "Развернуть" : "Свернуть"}
        </button>
"""

cs_name = "function ClientSettingsFields"
cs_start = t.find(cs_name)
if cs_start >= 0:
    cs_end = t.find("\nfunction ", cs_start + 1)
    if cs_end < 0:
        cs_end = len(t)
    cs_block = t[cs_start:cs_end]
    if stray_btn.strip() in cs_block:
        t = t[:cs_start] + cs_block.replace(stray_btn, "", 1) + t[cs_end:]

fp_name = "function FeaturesPanel()"
fp_start = t.find(fp_name)
if fp_start < 0:
    print("[patch-panel-hotfix-v7] skip: no FeaturesPanel", file=sys.stderr); print(0); raise SystemExit(0)
    sys.exit(0)
fp_end = t.find("\nfunction ", fp_start + 1)
if fp_end < 0:
    fp_end = len(t)
fp = t[fp_start:fp_end]

hdr_old = """      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold tracking-normal">Сеть и обход</h2>
          <p className="text-xs text-muted-foreground">
            Вкл/выкл zapret · tor · split · webtunnel · warp без переустановки. Состояние: /etc/olcrtc-manager/features.env. Логи клиента: раздел «Клиенты» → Logs (API /api/logs). Jitsi TLS: OLCRTC_JITSI_INSECURE_TLS=1 в panel.env.
          </p>
        </div>
      </div>
"""

hdr_new = """      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold tracking-normal">Сеть и обход</h2>
          <p className="text-xs text-muted-foreground">
            Вкл/выкл zapret · tor · split · webtunnel · warp без переустановки. Состояние: /etc/olcrtc-manager/features.env. Логи клиента: раздел «Клиенты» → Logs (API /api/logs). Jitsi TLS: OLCRTC_JITSI_INSECURE_TLS=1 в panel.env.
          </p>
        </div>
        <button
          type="button"
          className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs hover:bg-muted"
          onClick={() => {
            setCollapsed((v) => {
              const next = !v;
              try {
                localStorage.setItem("olc-network-bypass-collapsed", next ? "1" : "0");
              } catch {
                /* ignore */
              }
              return next;
            });
          }}
        >
          {collapsed ? "Развернуть" : "Свернуть"}
        </button>
      </div>
"""

net_idx = fp.find("Сеть и обход")
if net_idx >= 0 and '{collapsed ? "Развернуть" : "Свернуть"}' not in fp[net_idx : net_idx + 1200]:
    if hdr_old in fp:
        fp = fp.replace(hdr_old, hdr_new, 1)
        t = t[:fp_start] + fp + t[fp_end:]
    else:
        print("[patch-panel-hotfix-v7] warn: FeaturesPanel header pattern not found", file=sys.stderr); print(0); raise SystemExit(0)

if "olc-panel-hotfix-v7" not in t:
    if "/* olc-panel-hotfix-v6 */" in t:
        t = t.replace("/* olc-panel-hotfix-v6 */", "/* olc-panel-hotfix-v6 */\n/* olc-panel-hotfix-v7 */", 1)
    else:
        t = "/* olc-panel-hotfix-v7 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v7] ok"); print(0); raise SystemExit(0)
PY
