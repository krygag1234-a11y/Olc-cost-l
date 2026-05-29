#!/usr/bin/env bash
# Panel UI v3: per-feature log/settings, header toolbar, sync toggles, scoped delete busy.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'NetworkUIV3' "$MAIN_TSX" && { echo "[patch-panel-ui-v3] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# --- insert modals + helpers before HeaderNetworkToggles ---
insert_before = "function HeaderNetworkToggles()"
modals = r'''
const FEATURE_SETTINGS_HINTS: Record<FeatureName, { title: string; lines: string[] }> = {
  zapret: {
    title: "Zapret",
    lines: [
      "DPI-обход для direct egress (*.ru / CDN).",
      "Полная переустановка: OLCRTC_ZAPRET_REINSTALL=1 olc-update",
      "Синхронизация списков: olc-feature zapret reload",
    ],
  },
  tor: {
    title: "Tor",
    lines: [
      "SOCKS5 127.0.0.1:9050 + bridges в /etc/tor/bridges.conf",
      "Пул мостов: systemctl start olcrtc-tor-bridge-pool.service",
      "Без Tor split не имеет смысла — нет exit для остального трафика.",
    ],
  },
  split: {
    title: "Split routing",
    lines: [
      "Требует включённый Tor.",
      "*.ru / CDN → direct (+ zapret); остальное → Tor.",
      "Полное обновление списков: olc-update (не из панели).",
      "Файлы: /var/lib/olcrtc/lists/*.txt",
    ],
  },
  webtunnel: {
    title: "WebTunnel",
    lines: [
      "Бинарь: /usr/bin/webtunnel-client (mirror-cry)",
      "При выкл — Tor использует obfs4/snowflake.",
      "Включение может занять 1–2 мин (скачивание).",
    ],
  },
};

function FeatureLogsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  const [lines, setLines] = useState<string[]>([]);
  const [path, setPath] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
        const body = (await res.json()) as { lines?: string[]; path?: string };
        if (!cancelled) {
          setLines(body.lines ?? []);
          setPath(body.path ?? "");
        }
      } catch (e) {
        if (!cancelled) setLines([String(e)]);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [feature]);

  return (
    <Modal title={`Логи: ${feature}`} onClose={onClose}>
      <div className="p-4 space-y-3">
        <div className="flex items-center justify-between gap-2">
          {path && <div className="text-xs text-muted-foreground truncate">{path}</div>}
          <div className="flex shrink-0 gap-2">
            <button
              type="button"
              className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
              disabled={loading}
              onClick={async () => {
                try {
                  const res = await fetch(`/api/features/logs/${feature}`, { cache: "no-store" });
                  const body = (await res.json()) as { lines?: string[]; path?: string };
                  setLines(body.lines ?? []);
                  setPath(body.path ?? "");
                } catch (e) {
                  setLines([String(e)]);
                }
              }}
            >
              Обновить
            </button>
            <button
              type="button"
              className="inline-flex items-center rounded-md border border-border bg-background px-2 py-1 text-xs hover:bg-accent disabled:opacity-50"
              disabled={loading || lines.length === 0}
              onClick={async () => {
                const text = lines.join("\n");
                try {
                  await navigator.clipboard.writeText(text);
                } catch {
                  const textarea = document.createElement("textarea");
                  textarea.value = text;
                  textarea.style.position = "fixed";
                  textarea.style.opacity = "0";
                  document.body.appendChild(textarea);
                  textarea.select();
                  try {
                    document.execCommand("copy");
                  } finally {
                    document.body.removeChild(textarea);
                  }
                }
              }}
            >
              Копировать
            </button>
          </div>
        </div>
        {path && <div className="mb-2 text-xs text-muted-foreground">{path}</div>}
        <pre className="max-h-[60vh] overflow-auto rounded-md border border-border bg-background p-3 text-xs">
          {loading ? "Загрузка…" : lines.join("\n") || "(пусто)"}
        </pre>
      </div>
    </Modal>
  );
}

function FeatureSettingsModal({
  feature,
  onClose,
}: {
  feature: FeatureName;
  onClose: () => void;
}) {
  const info = FEATURE_SETTINGS_HINTS[feature];
  return (
    <Modal title={`Настройки: ${info.title}`} onClose={onClose}>
      <div className="space-y-2 p-4 text-sm text-muted-foreground">
        {info.lines.map((line) => (
          <p key={line}>{line}</p>
        ))}
      </div>
    </Modal>
  );
}

function notifyFeaturesChanged() {
  window.dispatchEvent(new CustomEvent("olc-features-changed"));
}

async function postFeatureToggle(name: FeatureName, enabled: boolean, flags?: Record<FeatureName, boolean>) {
  if (name === "split" && enabled && flags && !flags.tor) {
    throw new Error("Сначала включите Tor — split маршрутизирует остальной трафик через exit");
  }
  const res = await fetch(`/api/features/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ enabled }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok && !body?.warning) {
    throw new Error(body?.error || `HTTP ${res.status}`);
  }
  notifyFeaturesChanged();
  return body;
}

'''

if insert_before in t and "FeatureLogsModal" not in t:
    t = t.replace(insert_before, modals + insert_before, 1)

# --- Replace HeaderNetworkToggles ---
old_header = '''function HeaderNetworkToggles() {
  const [flags, setFlags] = useState<Record<FeatureName, boolean> | null>(null);
  const [busy, setBusy] = useState<FeatureName | null>(null);

  const load = async () => {
    try {
      const res = await fetch("/api/features", { cache: "no-store" });
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
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok && !body?.warning) throw new Error(body?.error || `HTTP ${res.status}`);
      await load();
      window.dispatchEvent(new CustomEvent("olc-features-changed"));
    } finally {
      setBusy(null);
    }
  };

  if (!flags) return null;

  const items: { name: FeatureName; label: string }[] = [
    { name: "zapret", label: "Zp" },
    { name: "tor", label: "Tor" },
    { name: "split", label: "Sp" },
    { name: "webtunnel", label: "Wt" },
  ];

  return (
    <div className="flex flex-wrap items-center gap-1 rounded-md border border-border bg-muted/40 px-1 py-0.5">
      {items.map((it) => {
        const on = Boolean(flags[it.name]);
        return (
          <button
            key={it.name}
            type="button"
            title={`${it.name}: ${on ? "on" : "off"}`}
            className={`inline-flex h-7 min-w-[2.25rem] items-center justify-center rounded px-1.5 text-[11px] font-medium disabled:opacity-50 ${
              on ? "bg-emerald-500/25 text-emerald-300" : "text-muted-foreground hover:bg-muted"
            }`}
            disabled={busy !== null}
            onClick={() => void toggle(it.name)}
          >
            {busy === it.name ? "…" : it.label}
          </button>
        );
      })}
    </div>
  );
}'''

new_header = '''function HeaderNetworkToggles() { // NetworkUIV3
  const [flags, setFlags] = useState<Record<FeatureName, boolean> | null>(null);
  const [busy, setBusy] = useState<FeatureName | null>(null);
  const [logFeature, setLogFeature] = useState<FeatureName | null>(null);
  const [settingsFeature, setSettingsFeature] = useState<FeatureName | null>(null);
  const [err, setErr] = useState("");

  const load = async () => {
    try {
      const res = await fetch("/api/features", { cache: "no-store" });
      if (!res.ok) return;
      const body = (await res.json()) as { flags?: Record<FeatureName, boolean> };
      setFlags(body.flags ?? null);
      setErr("");
    } catch (e) {
      setErr(String(e));
    }
  };

  useEffect(() => {
    void load();
    const onChange = () => void load();
    window.addEventListener("olc-features-changed", onChange);
    return () => window.removeEventListener("olc-features-changed", onChange);
  }, []);

  const toggle = async (name: FeatureName) => {
    if (!flags) return;
    setBusy(name);
    setErr("");
    try {
      const enabled = !flags[name];
      await postFeatureToggle(name, enabled, flags);
      await load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };

  const items: { name: FeatureName; label: string }[] = [
    { name: "zapret", label: "Zp" },
    { name: "tor", label: "Tor" },
    { name: "split", label: "Sp" },
    { name: "webtunnel", label: "Wt" },
  ];

  return (
    <>
      <div className="flex flex-wrap items-center gap-2 rounded-md border border-border bg-muted/40 px-2 py-1">
        {items.map((it) => {
          const on = Boolean(flags?.[it.name]);
          const splitBlocked = it.name === "split" && !flags?.tor;
          return (
            <div key={it.name} className="flex items-center gap-0.5 rounded border border-border/60 bg-background/50 pr-0.5">
              <button
                type="button"
                title={splitBlocked ? "Сначала Tor" : `${it.name}: ${on ? "on" : "off"}`}
                className={`inline-flex h-7 min-w-[2rem] items-center justify-center rounded-l px-1.5 text-[11px] font-medium disabled:opacity-50 ${
                  on ? "bg-emerald-500/25 text-emerald-300" : "text-muted-foreground hover:bg-muted"
                }`}
                disabled={busy !== null || splitBlocked}
                onClick={() => void toggle(it.name)}
              >
                {busy === it.name ? "…" : it.label}
              </button>
              <button
                type="button"
                title="Логи"
                className="inline-flex h-7 w-7 items-center justify-center text-muted-foreground hover:bg-muted hover:text-foreground"
                onClick={() => setLogFeature(it.name)}
              >
                <Terminal className="h-3.5 w-3.5" />
              </button>
              <button
                type="button"
                title="Настройки"
                className="inline-flex h-7 w-7 items-center justify-center text-muted-foreground hover:bg-muted hover:text-foreground"
                onClick={() => setSettingsFeature(it.name)}
              >
                <Settings className="h-3.5 w-3.5" />
              </button>
            </div>
          );
        })}
      </div>
      {err && <span className="max-w-xs truncate text-xs text-red-400" title={err}>{err}</span>}
      {logFeature && <FeatureLogsModal feature={logFeature} onClose={() => setLogFeature(null)} />}
      {settingsFeature && <FeatureSettingsModal feature={settingsFeature} onClose={() => setSettingsFeature(null)} />}
    </>
  );
}'''

if old_header in t:
    t = t.replace(old_header, new_header, 1)
else:
    print("[patch-panel-ui-v3] WARN: HeaderNetworkToggles block not matched"); raise SystemExit(0)

# --- FeaturesPanel: sync + tor guard + log/settings buttons ---
t = t.replace(
    "function FeaturesPanel() { // FeaturesPanelV2",
    "function FeaturesPanel() { // FeaturesPanelV2 NetworkUIV3",
    1,
)

old_fp_effect = """  useEffect(() => {
    void load();
  }, []);"""

new_fp_effect = """  useEffect(() => {
    void load();
    const onChange = () => void load();
    window.addEventListener("olc-features-changed", onChange);
    return () => window.removeEventListener("olc-features-changed", onChange);
  }, []);"""

if old_fp_effect in t:
    t = t.replace(old_fp_effect, new_fp_effect, 1)

old_fp_toggle = """  const toggle = async (name: FeatureName, enabled: boolean) => {
    setBusy(name);
    setErr("");
    try {
      const res = await fetch(`/api/features/${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
      await load();
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(null);
    }
  };"""

new_fp_toggle = """  const [logFeature, setLogFeature] = useState<FeatureName | null>(null);
  const [settingsFeature, setSettingsFeature] = useState<FeatureName | null>(null);

  const toggle = async (name: FeatureName, enabled: boolean) => {
    setBusy(name);
    setErr("");
    try {
      await postFeatureToggle(name, enabled, data?.flags);
      await load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };"""

if old_fp_toggle in t and "const [logFeature, setLogFeature]" not in t.split("function FeaturesPanel")[1].split("function App")[0]:
    t = t.replace(old_fp_toggle, new_fp_toggle, 1)

# Add log/settings buttons in feature rows
old_row_btn = """                <button
                  className={`inline-flex h-8 items-center gap-2 rounded-md border px-3 text-sm disabled:opacity-60 ${enabled ? "border-red-500/40 hover:bg-red-500/10" : "border-emerald-500/40 hover:bg-emerald-500/10"}`}
                  disabled={busy !== null}
                  onClick={() => void toggle(row.name, !enabled)}
                >
                  {busy === row.name ? "…" : enabled ? "Выключить" : "Включить"}
                </button>"""

new_row_btn = """                <div className="flex flex-wrap gap-1">
                  <button
                    type="button"
                    title="Логи"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted"
                    onClick={() => setLogFeature(row.name)}
                  >
                    <Terminal className="h-4 w-4" />
                  </button>
                  <button
                    type="button"
                    title="Настройки"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-md border border-border hover:bg-muted"
                    onClick={() => setSettingsFeature(row.name)}
                  >
                    <Settings className="h-4 w-4" />
                  </button>
                  <button
                    className={`inline-flex h-8 items-center gap-2 rounded-md border px-3 text-sm disabled:opacity-60 ${enabled ? "border-red-500/40 hover:bg-red-500/10" : "border-emerald-500/40 hover:bg-emerald-500/10"}`}
                    disabled={busy !== null || (row.name === "split" && !enabled && !data.flags?.tor)}
                    onClick={() => void toggle(row.name, !enabled)}
                  >
                    {busy === row.name ? "…" : enabled ? "Выключить" : "Включить"}
                  </button>
                </div>"""

if old_row_btn in t:
    t = t.replace(old_row_btn, new_row_btn, 1)

# Modals at end of FeaturesPanel return
old_fp_end = """    </section>
  );
}


function App() {"""

new_fp_end = """      {logFeature && <FeatureLogsModal feature={logFeature} onClose={() => setLogFeature(null)} />}
      {settingsFeature && <FeatureSettingsModal feature={settingsFeature} onClose={() => setSettingsFeature(null)} />}
    </section>
  );
}


function App() {"""

if old_fp_end in t and "logFeature && <FeatureLogsModal" not in t.split("function FeaturesPanel")[1]:
    t = t.replace(old_fp_end, new_fp_end, 1)

# --- App: scoped pending for location delete (must not attach to LoginView's busy) ---
app_idx = t.find("function App() {")
if app_idx >= 0:
    app_end = t.find("\nfunction ", app_idx + 12)
    if app_end < 0:
        app_end = len(t)
    app_chunk = t[app_idx:app_end]
    if "const [pendingLocations, setPendingLocations]" not in app_chunk:
        new_chunk = app_chunk.replace(
            "  const [busy, setBusy] = useState(false);",
            "  const [busy, setBusy] = useState(false);\n  const [pendingLocations, setPendingLocations] = useState<Record<string, string>>({});",
            1,
        )
        if new_chunk != app_chunk:
            t = t[:app_idx] + new_chunk + t[app_end:]

loc_key_fn = """
  const locationActionKey = (clientID: string, location: LocationState) =>
    `${clientID}:${location.room_id}:${location.transport}`;
"""

if "locationActionKey" not in t:
    t = t.replace("  const clients = state?.clients ?? [];", loc_key_fn + "\n  const clients = state?.clients ?? [];", 1)

old_del_loc = """  const deleteLocation = (clientID: string, location: LocationState) =>
    runAction(async () => {
      if (!window.confirm(`Удалить локацию ${location.name || location.room_id}?`)) return;
      await request(`/api/clients/${encodeURIComponent(clientID)}/locations/${encodeURIComponent(location.room_id)}`, {
        method: "DELETE",
      });
    }, "Локация удалена");"""

new_del_loc = """  const deleteLocation = async (clientID: string, location: LocationState) => {
    if (!window.confirm(`Удалить локацию ${location.name || location.room_id}?`)) return;
    const key = locationActionKey(clientID, location);
    setPendingLocations((p) => ({ ...p, [key]: "Удаление… (~5–15 с)" }));
    setNotice("Удаление локации… остальные кнопки доступны");
    try {
      await request(`/api/clients/${encodeURIComponent(clientID)}/locations/${encodeURIComponent(location.room_id)}`, {
        method: "DELETE",
      });
      setNotice("Локация удалена (инстанс останавливается в фоне)");
      await loadState();
      await loadMetrics();
    } catch (err) {
      setNotice(err instanceof Error ? err.message : String(err));
    } finally {
      setPendingLocations((p) => {
        const next = { ...p };
        delete next[key];
        return next;
      });
    }
  };"""

if old_del_loc in t:
    t = t.replace(old_del_loc, new_del_loc, 1)

# Location row buttons: use pendingLocations instead of global busy where possible
t = t.replace(
    "disabled={busy}\n                                      onClick={() => deleteLocation(client.client_id, loc)}",
    "disabled={Boolean(pendingLocations[locationActionKey(client.client_id, loc)])}\n                                      onClick={() => void deleteLocation(client.client_id, loc)}",
    1,
)

t = t.replace(
    "disabled={busy}\n                                      onClick={() => restartLocation(client.client_id, loc)}",
    "disabled={Boolean(pendingLocations[locationActionKey(client.client_id, loc)])}\n                                      onClick={() => restartLocation(client.client_id, loc)}",
    1,
)

t = t.replace(
    "disabled={busy || !loc.runtime.running}\n                                      onClick={() => stopLocation(client.client_id, loc)}",
    "disabled={Boolean(pendingLocations[locationActionKey(client.client_id, loc)]) || !loc.runtime.running}\n                                      onClick={() => stopLocation(client.client_id, loc)}",
    1,
)

# --- Instance logs: robust clipboard copy with fallback (HTTP-friendly) ---
old_copy_logs = """  const copyLogs = () =>
    runAction(async () => {
      await navigator.clipboard.writeText(
        logs.map((line) => `[${line.time}] ${line.stream}: ${line.line}`).join("\\n"),
      );
    }, "Логи скопированы");"""

new_copy_logs = """  const copyLogs = () =>
    runAction(async () => {
      const text = logs.map((line) => `[${line.time}] ${line.stream}: ${line.line}`).join("\\n");
      try {
        await navigator.clipboard.writeText(text);
      } catch {
        const textarea = document.createElement("textarea");
        textarea.value = text;
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.appendChild(textarea);
        textarea.select();
        try {
          document.execCommand("copy");
        } finally {
          document.body.removeChild(textarea);
        }
      }
    }, "Логи скопированы");"""

if old_copy_logs in t:
    t = t.replace(old_copy_logs, new_copy_logs, 1)

p.write_text(t)
print("[patch-panel-ui-v3] ok"); raise SystemExit(0)
PY
