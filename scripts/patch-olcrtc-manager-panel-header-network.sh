#!/usr/bin/env bash
# Quick network toggles in header (next to Settings / Refresh).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'HeaderNetworkToggles' "$MAIN_TSX" && { echo "[patch-panel-header-net] already applied"; exit 0; }
grep -q 'FeaturesPanel' "$MAIN_TSX" || { echo "[patch-panel-header-net] skip: no FeaturesPanel"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

component = """
function HeaderNetworkToggles() {
  const [flags, setFlags] = useState<Record<FeatureName, boolean> | null>(null);
  const [busy, setBusy] = useState<FeatureName | null>(null);

  const load = async () => {
    try {
      const res = await fetch(\"/api/features\", { cache: \"no-store\" });
      if (!res.ok) return;
      const body = (await res.json()) as { flags?: Record<FeatureName, boolean> };
      setFlags(body.flags ?? null);
    } catch {
      /* ignore */
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const toggle = async (name: FeatureName) => {
    if (!flags) return;
    setBusy(name);
    try {
      const enabled = !flags[name];
      const res = await fetch(`/api/features/${name}`, {
        method: \"POST\",
        headers: { \"Content-Type\": \"application/json\" },
        body: JSON.stringify({ enabled }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok && !body?.warning) throw new Error(body?.error || `HTTP ${res.status}`);
      await load();
      window.dispatchEvent(new CustomEvent(\"olc-features-changed\"));
    } finally {
      setBusy(null);
    }
  };

  if (!flags) return null;

  const items: { name: FeatureName; label: string }[] = [
    { name: \"zapret\", label: \"Zp\" },
    { name: \"tor\", label: \"Tor\" },
    { name: \"split\", label: \"Sp\" },
    { name: \"webtunnel\", label: \"Wt\" },
  ];

  return (
    <div className=\"flex flex-wrap items-center gap-1 rounded-md border border-border bg-muted/40 px-1 py-0.5\">
      {items.map((it) => {
        const on = Boolean(flags[it.name]);
        return (
          <button
            key={it.name}
            type=\"button\"
            title={`${it.name}: ${on ? \"on\" : \"off\"}`}
            className={`inline-flex h-7 min-w-[2.25rem] items-center justify-center rounded px-1.5 text-[11px] font-medium disabled:opacity-50 ${
              on ? \"bg-emerald-500/25 text-emerald-300\" : \"text-muted-foreground hover:bg-muted\"
            }`}
            disabled={busy !== null}
            onClick={() => void toggle(it.name)}
          >
            {busy === it.name ? \"…\" : it.label}
          </button>
        );
      })}
    </div>
  );
}
"""

# Insert before FeaturesPanel function (reuse FeatureName if exists)
if "function HeaderNetworkToggles" not in t:
    t = t.replace("function FeaturesPanel() { // FeaturesPanelV2", component + "\nfunction FeaturesPanel() { // FeaturesPanelV2", 1)
    if "function HeaderNetworkToggles" not in t:
        t = t.replace("function FeaturesPanel() {", component + "\nfunction FeaturesPanel() {", 1)

# Header: before Settings button
needle = """            <button
              className=\"inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80\"
              onClick={openSettings}
            >
              <Settings className=\"h-4 w-4\" />
              Настройки
            </button>"""

insert = """            <HeaderNetworkToggles />
            <button
              className=\"inline-flex h-9 items-center gap-2 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80\"
              onClick={openSettings}
            >
              <Settings className=\"h-4 w-4\" />
              Настройки
            </button>"""

if needle in t and "HeaderNetworkToggles" not in t.split("Настройки")[0][-200:]:
    t = t.replace(needle, insert, 1)

# FeaturesPanel reload on header toggle
if "olc-features-changed" not in t:
    t = t.replace(
        "  useEffect(() => {\n    void load();\n  }, []);",
        "  useEffect(() => {\n    void load();\n    const onChange = () => void load();\n    window.addEventListener(\"olc-features-changed\", onChange);\n    return () => window.removeEventListener(\"olc-features-changed\", onChange);\n  }, []);",
        1,
    )

p.write_text(t)
print("[patch-panel-header-net] ok")
PY
