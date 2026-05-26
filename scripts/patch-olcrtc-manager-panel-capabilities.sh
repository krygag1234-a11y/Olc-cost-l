#!/usr/bin/env bash
# UI: hide Zp/Tor/Sp/Мосты when not installed (GET /api/capabilities).
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'useCapabilities' "$MAIN_TSX" && grep -q 'items.filter((it) => visible' "$MAIN_TSX" && { echo "[patch-panel-capabilities] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

hook = r'''
type Capabilities = {
  panel_version?: string;
  deploy_profile?: string;
  components?: Record<string, { installed?: boolean; enabled?: boolean; label?: string; requires?: string[] }>;
};

function useCapabilities() {
  const [caps, setCaps] = useState<Capabilities | null>(null);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/capabilities", { cache: "no-store" });
        if (!res.ok) return;
        const body = (await res.json()) as Capabilities;
        if (!cancelled) setCaps(body);
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);
  const visible = (name: FeatureName) => {
    const key = name === "webtunnel" ? "bridges" : name;
    const c = caps?.components?.[key];
    if (!c) return true;
    return c.installed !== false;
  };
  return { caps, visible };
}

'''

anchor = "function HeaderNetworkToggles()"
if "function useCapabilities" not in t and anchor in t:
    t = t.replace(anchor, hook + "\n" + anchor, 1)

# HeaderNetworkToggles: add visible check
for old_h, new_h in [
    (
        "function HeaderNetworkToggles() {\n  const [flags, setFlags]",
        "function HeaderNetworkToggles() {\n  const { visible } = useCapabilities();\n  const [flags, setFlags]",
    ),
    (
        "function HeaderNetworkToggles() { // NetworkUIV3\n  const [flags, setFlags]",
        "function HeaderNetworkToggles() { // NetworkUIV3\n  const { visible } = useCapabilities();\n  const [flags, setFlags]",
    ),
]:
    if old_h in t:
        t = t.replace(old_h, new_h, 1)

if "{items.filter((it) => visible(it.name)).map((it) =>" not in t:
    t = t.replace("{items.map((it) => {", "{items.filter((it) => visible(it.name)).map((it) => {", 1)

# Wrap map in header - find NETWORK_UI_ROWS map
if "NETWORK_UI_ROWS.map" in t and ".filter((row) => visible(row.name))" not in t:
    t = t.replace(
        "NETWORK_UI_ROWS.map((row) => {",
        "NETWORK_UI_ROWS.filter((row) => visible(row.name)).map((row) => {",
        1,
    )

# FeaturesPanel
for old_fp, new_fp in [
    (
        "function FeaturesPanel() {\n  const [data, setData]",
        "function FeaturesPanel() {\n  const { visible } = useCapabilities();\n  const [data, setData]",
    ),
    (
        "function FeaturesPanel() { // FeaturesPanelV2 NetworkUIV3\n  const [data, setData]",
        "function FeaturesPanel() { // FeaturesPanelV2 NetworkUIV3\n  const { visible } = useCapabilities();\n  const [data, setData]",
    ),
]:
    if old_fp in t:
        t = t.replace(old_fp, new_fp, 1)

if "rows.map((row)" in t and "rows.filter((row) => visible(row.name))" not in t.split("function FeaturesPanel")[1]:
    t = t.replace(
        "          {rows.map((row) => {",
        "          {rows.filter((row) => visible(row.name)).map((row) => {",
        1,
    )

# Rename webtunnel label to Мосты in UI rows if present
t = t.replace('label: "Wt"', 'label: "Мосты"', 2)
t = t.replace('title: "WebTunnel"', 'title: "Мосты"', 1)

p.write_text(t)
print("[patch-panel-capabilities] ok")
PY
