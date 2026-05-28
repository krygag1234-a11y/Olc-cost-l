#!/usr/bin/env bash
# Add a 'Features' card to the admin UI (main.tsx) that calls /api/features.
# Lets the operator toggle zapret/tor/split/webtunnel from the panel.
set -euo pipefail

MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-panel-features] skip: $MAIN_TSX not found"; exit 0; }

if grep -q "FeaturesPanel" "$MAIN_TSX"; then
  echo "[patch-panel-features] already applied"
  exit 0
fi

python3 - "$MAIN_TSX" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text()

if "FeaturesPanel" in src:
    print("[patch-panel-features] already applied"); print(0); raise SystemExit(0)
    sys.exit(0)

# 1. Insert FeaturesPanel component definition before `function App()`
component = """
type FeatureName = \"zapret\" | \"tor\" | \"split\" | \"webtunnel\";

interface FeaturesResponse {
  flags: Record<FeatureName, boolean>;
  live: Record<string, string>;
  script: string;
}

function FeaturesPanel() {
  const [data, setData] = useState<FeaturesResponse | null>(null);
  const [busy, setBusy] = useState<FeatureName | null>(null);
  const [err, setErr] = useState<string>(\"\");

  const load = async () => {
    try {
      const res = await fetch(\"/api/features\", { cache: \"no-store\" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setData(await res.json());
      setErr(\"\");
    } catch (e) {
      setErr(String(e));
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const toggle = async (name: FeatureName, enabled: boolean) => {
    setBusy(name);
    setErr(\"\");
    try {
      const res = await fetch(`/api/features/${name}`, {
        method: \"POST\",
        headers: { \"Content-Type\": \"application/json\" },
        body: JSON.stringify({ enabled }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
      await load();
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(null);
    }
  };

  if (!data && !err) {
    return null;
  }

  const rows: { name: FeatureName; label: string; hint: string }[] = [
    { name: \"zapret\", label: \"Zapret\", hint: \"DPI bypass for blocked .ru on direct egress\" },
    { name: \"tor\",     label: \"Tor\",     hint: \"SOCKS5 9050 + bridges (RU VPS)\" },
    { name: \"split\",   label: \"Split routing\", hint: \"*.ru / CDN → direct; rest → Tor\" },
    { name: \"webtunnel\", label: \"WebTunnel bridges\", hint: \"prebuilt binary from mirror-cry\" },
  ];

  return (
    <section className=\"mt-4 rounded-lg border border-border bg-card p-4\">
      <div className=\"flex flex-wrap items-center justify-between gap-3\">
        <div>
          <h2 className=\"text-lg font-semibold tracking-normal\">Network features</h2>
          <p className=\"text-xs text-muted-foreground\">
            On/off для zapret · tor · split · webtunnel без переустановки. State пишется в /etc/olcrtc-manager/features.env.
          </p>
        </div>
        <button
          className=\"inline-flex h-8 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60\"
          disabled={busy !== null}
          onClick={() => void load()}
        >
          Обновить
        </button>
      </div>
      {err && <div className=\"mt-3 rounded-md border border-red-500/40 bg-red-500/10 p-3 text-xs text-red-300\">{err}</div>}
      {data && (
        <div className=\"mt-4 grid gap-2\">
          {rows.map((row) => {
            const enabled = Boolean(data.flags?.[row.name]);
            return (
              <div key={row.name} className=\"flex flex-wrap items-center justify-between gap-3 rounded-md border border-border bg-background p-3\">
                <div className=\"min-w-0\">
                  <div className=\"flex items-center gap-2\">
                    <span className=\"font-medium\">{row.label}</span>
                    <span className={`inline-flex h-5 items-center rounded-full px-2 text-[10px] uppercase tracking-wider ${enabled ? \"bg-emerald-500/20 text-emerald-300\" : \"bg-zinc-500/20 text-zinc-300\"}`}>
                      {enabled ? \"on\" : \"off\"}
                    </span>
                    {data.live?.[row.name] && (
                      <span className=\"text-[10px] uppercase tracking-wider text-muted-foreground\">live: {data.live[row.name]}</span>
                    )}
                  </div>
                  <div className=\"text-xs text-muted-foreground\">{row.hint}</div>
                </div>
                <button
                  className={`inline-flex h-8 items-center gap-2 rounded-md border px-3 text-sm disabled:opacity-60 ${enabled ? \"border-red-500/40 hover:bg-red-500/10\" : \"border-emerald-500/40 hover:bg-emerald-500/10\"}`}
                  disabled={busy !== null}
                  onClick={() => void toggle(row.name, !enabled)}
                >
                  {busy === row.name ? \"…\" : enabled ? \"Disable\" : \"Enable\"}
                </button>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
"""

anchor = "\nfunction App() {"
idx = src.find(anchor)
if idx < 0:
    print("[patch-panel-features] App() not found"); print(0); raise SystemExit(0)
src = src[:idx] + component + "\n" + src[idx:]

# 2. Render <FeaturesPanel /> right after the StatCard section
stat_close = "</section>\n\n        <section className=\"mt-4 rounded-lg border border-border bg-card p-4\">\n          <div className=\"flex flex-wrap items-center justify-between gap-3\">\n            <div>\n              <h2 className=\"text-lg font-semibold tracking-normal\">Клиенты</h2>"
insert = "</section>\n\n        <FeaturesPanel />\n\n        <section className=\"mt-4 rounded-lg border border-border bg-card p-4\">\n          <div className=\"flex flex-wrap items-center justify-between gap-3\">\n            <div>\n              <h2 className=\"text-lg font-semibold tracking-normal\">Клиенты</h2>"
if stat_close in src:
    src = src.replace(stat_close, insert, 1)
else:
    # Fallback: insert after first </section> following App()
    apos = src.find("function App() {")
    sec_close = src.find("</section>", apos)
    if sec_close < 0:
        print("[patch-panel-features] cannot locate insert position"); print(0); raise SystemExit(0)
    src = src[: sec_close + len("</section>")] + "\n\n        <FeaturesPanel />\n" + src[sec_close + len("</section>"):]

p.write_text(src)
print("[patch-panel-features] applied"); print(0); raise SystemExit(0)
PY
