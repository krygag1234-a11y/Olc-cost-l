#!/usr/bin/env bash
# Hotfix v17: autodetect layout, errors menu modal, bridges log always when open.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
# Re-run if modal wiring missing (partial apply).
if grep -q 'olc-panel-hotfix-v17' "$MAIN_TSX"; then
  if python3 - "$MAIN_TSX" <<'CHK'
import sys
from pathlib import Path
t = Path(sys.argv[1]).read_text()
err = t.split("function ErrorsSummaryButton", 1)[1].split("function UpdateAvailableToast", 1)[0]
raise SystemExit(0 if "autodetectOpen &&" in err else 1)
CHK
  then
    echo "[patch-panel-hotfix-v17] already applied"
    exit 0
  fi
  echo "[patch-panel-hotfix-v17] re-run (modal missing)"
fi

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Remove duplicate autodetect block; fix wrapper around MainSettingsAutodetectLink.
dup = """            {/* autodetect-settings-inline-v6 */}
            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <div className="text-sm font-medium text-foreground">Автодетектор</div>
              <p className="text-xs text-muted-foreground">Периодически ищет ошибки в логах и состоянии сервисов.</p>
              <button type="button" className="w-fit rounded border border-border px-3 py-2 text-xs hover:bg-muted" onClick={() => setShowAutodetectInline((v) => !v)}>
                Настройки уведомлений автодетектора
              </button>
              {showAutodetectInline && (
                <div className="rounded-md border border-dashed border-border bg-card p-3">
                  <AutodetectNotificationSettingsPanel />
                </div>
              )}
            </section>

"""
if dup in t:
    t = t.replace(dup, "", 1)

broken = """            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
            </div>


"""
fixed = """            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
              {showAutodetectInline && (
                <div className="rounded-md border border-dashed border-border bg-card p-3">
                  <AutodetectNotificationSettingsPanel />
                </div>
              )}
            </section>

"""
if broken in t:
    t = t.replace(broken, fixed, 1)
elif "MainSettingsAutodetectLink" in t and "olc-panel-hotfix-v12" not in t:
    pass

# Errors menu: wire autodetect modal (state without modal was a v12 regression).
err_blk = t.split("function ErrorsSummaryButton", 1)[1].split("function UpdateAvailableToast", 1)[0]
if "setAutodetectOpen(true)" not in err_blk:
    t = t.replace(
        'onClick={() => { setOpen(false); window.dispatchEvent(new Event("olc-open-autodetect-settings")); }}',
        'onClick={() => { setOpen(false); setAutodetectOpen(true); }}',
        1,
    )
    err_blk = t.split("function ErrorsSummaryButton", 1)[1].split("function UpdateAvailableToast", 1)[0]
if "autodetectOpen &&" not in err_blk:
    modal = """
      {autodetectOpen && (
        <Modal title="Настройки автодетектора" onClose={() => setAutodetectOpen(false)}>
          <div className="max-h-[70vh] overflow-auto p-4">
            <AutodetectNotificationSettingsPanel onClose={() => setAutodetectOpen(false)} />
          </div>
        </Modal>
      )}"""
    i0 = t.index("function ErrorsSummaryButton")
    i1 = t.index("function UpdateAvailableToast", i0)
    blk = t[i0:i1]
    needle = "        </Modal>\n      )}\n    </>"
    if needle in blk:
        blk = blk.replace(needle, "        </Modal>\n      )}" + modal + "\n    </>", 1)
        t = t[:i0] + blk + t[i1:]

# Bridges: show log panel whenever poolUiOpen (not poolUiOpen && bridgePoolUiVisible).
t = t.replace(
    "const poolUiActive = poolUiOpen && bridgePoolUiVisible(poolJob);",
    "const poolUiActive = poolUiOpen;",
    1,
)

# On mount: reopen log if pool job still running.
if "pool_job.status" not in t.split("BRIDGE_POOL_UI_KEY")[1].split("function BridgesSettingsFields")[1][:2500]:
    old_sess = """      const st = JSON.parse(raw) as { open?: boolean; hint?: string; job?: Record<string, unknown> };
      if (st.job && bridgePoolUiVisible(st.job)) {
        setPoolUiOpen(Boolean(st.open));
        if (st.hint) setPoolHint(st.hint);
      }"""
    new_sess = """      const st = JSON.parse(raw) as { open?: boolean; hint?: string; job?: Record<string, unknown> };
      const pj = st.job ?? {};
      const stt = String(pj.status ?? "idle");
      if (st.open || stt === "running" || bridgePoolUiVisible(pj)) {
        setPoolUiOpen(true);
        if (st.hint) setPoolHint(st.hint);
      }"""
    if old_sess in t:
        t = t.replace(old_sess, new_sess, 1)

if "olc-panel-hotfix-v17" not in t:
    if "/* olc-panel-hotfix-v16 */" in t:
        t = t.replace("/* olc-panel-hotfix-v16 */", "/* olc-panel-hotfix-v16 */\n/* olc-panel-hotfix-v17 */", 1)
    else:
        t = "/* olc-panel-hotfix-v17 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v17] ok")
PY
