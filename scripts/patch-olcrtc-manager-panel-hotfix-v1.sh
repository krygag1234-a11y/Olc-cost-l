#!/usr/bin/env bash
# Hotfix v1: restore network panel UX and autodetect opening flow.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v1' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v1] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Restore collapse/expand control in "Сеть и обход" header.
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
if hdr_old in t and '{collapsed ? "Развернуть" : "Свернуть"}' not in t[t.find("Сеть и обход"):t.find("Сеть и обход")+1200]:
    t = t.replace(hdr_old, hdr_new, 1)

# Do not allow bridges without Tor in UI.
t = t.replace(
    '(row.name === "split" && !enabled && !data.flags?.tor) ||',
    '(row.name === "split" && !enabled && !data.flags?.tor) ||\n                      (row.name === "webtunnel" && !enabled && !data.flags?.tor) ||',
    1,
)

# Re-add global listener that opens settings + autodetect panel.
if 'olc-open-autodetect-settings' not in t[t.find("useEffect(() => {", t.find("function App()")):t.find("const openCreate =", t.find("function App()"))]:
    marker = '  const openSettings = async () => {'
    listener = """
  useEffect(() => {
    const onOpenAutodetect = () => {
      setShowSettings(true);
      setShowAutodetectInline(true);
      void loadSettings().catch((err) => setNotice(err instanceof Error ? err.message : String(err)));
    };
    window.addEventListener("olc-open-autodetect-settings", onOpenAutodetect);
    return () => window.removeEventListener("olc-open-autodetect-settings", onOpenAutodetect);
  }, []);

"""
    if marker in t:
        t = t.replace(marker, listener + marker, 1)

# Settings button in Errors modal: dispatch event first, then close.
t = t.replace(
    'onClick={() => { setOpen(false); window.dispatchEvent(new Event("olc-open-autodetect-settings")); }}',
    'onClick={() => { window.dispatchEvent(new Event("olc-open-autodetect-settings")); setOpen(false); }}',
    1,
)

# Move autodetect block from footer buttons row to dedicated section above admin password.
old_inline = '            <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />'
if old_inline in t:
    t = t.replace(old_inline, "", 1)
    pass_sec = '            <section className="grid gap-3 rounded-md border border-border bg-background p-4">\n              <div className="text-sm font-medium text-foreground">Пароль администратора</div>'
    insert = """            <section className="grid gap-3 rounded-md border border-border bg-background p-4">
              <MainSettingsAutodetectLink expanded={showAutodetectInline} onToggle={() => setShowAutodetectInline((v) => !v)} />
            </section>

""" + pass_sec
    if pass_sec in t:
        t = t.replace(pass_sec, insert, 1)

if "olc-panel-hotfix-v1" not in t:
    t = t.replace("/* olc-panel-ui-v10 */", "/* olc-panel-ui-v10 */\n/* olc-panel-hotfix-v1 */", 1)

p.write_text(t)
print("[patch-panel-hotfix-v1] ok"); print(0); raise SystemExit(0)
PY
