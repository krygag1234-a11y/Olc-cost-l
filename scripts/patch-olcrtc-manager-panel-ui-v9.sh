#!/usr/bin/env bash
# UI v9: fix Profile rename save + sync with general settings.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-v9' "$MAIN_TSX" && { echo "[patch-panel-ui-v9] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
t = t.replace("/* olc-panel-ui-v8 */", "/* olc-panel-ui-v9 */", 1) if "olc-panel-ui-v8" in t else t.replace(
    "import React, {", "/* olc-panel-ui-v9 */\nimport React, {", 1
)

# saveSettingsName helper in App scope
if "const saveSettingsName = async (nextName: string) => {" not in t:
    t = t.replace(
        '  const saveSettings = async () => {',
        '''  const saveSettingsName = async (nextName: string) => {
    const name = nextName.trim();
    if (!name) throw new Error("Укажи название сервера");
    const port = Number(settingsForm.port);
    if (!Number.isInteger(port) || port <= 0 || port > 65535) throw new Error("Порт должен быть от 1 до 65535");
    const res = await request("/api/settings", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name,
        port,
        subscription_path: settingsForm.subscription_path.trim(),
        refresh: cleanRefresh(settingsForm.refresh),
      }),
    });
    const body = (await res.json()) as SettingsState;
    setSettings(body);
    setSettingsForm({
      name: body.name,
      port: String(body.port),
      subscription_path: body.subscription_path,
      refresh: body.refresh ?? "",
    });
    await loadState();
    await loadAudit();
    setNotice("Профиль переименован");
  };

  const saveSettings = async () => {''',
        1,
    )

# Make ProfileStatCard show save errors
if "const [err, setErr] = useState(\"\");" not in t.split("function ProfileStatCard")[1].split("function StatCard")[0]:
    t = t.replace(
        '  const [editing, setEditing] = useState(false);\n  const [val, setVal] = useState(name);',
        '  const [editing, setEditing] = useState(false);\n  const [val, setVal] = useState(name);\n  const [err, setErr] = useState("");',
        1,
    )
    t = t.replace(
        'onClick={() => void onSave(val).then(() => setEditing(false))}',
        '''onClick={() =>
            void onSave(val)
              .then(() => {
                setErr("");
                setEditing(false);
              })
              .catch((e) => setErr(e instanceof Error ? e.message : String(e)))
          }''',
        1,
    )
    t = t.replace(
        "      )}\n    </div>",
        "      )}\n      {err && <p className=\"mt-2 text-xs text-destructive\">{err}</p>}\n    </div>",
        1,
    )

p.write_text(t)
print("[patch-panel-ui-v9] ok")
PY
