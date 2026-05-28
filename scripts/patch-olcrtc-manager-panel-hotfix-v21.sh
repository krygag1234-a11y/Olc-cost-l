#!/usr/bin/env bash
# Hotfix v21: Jitsi-only URL validation; autodetect polling in Errors button + Bell.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-hotfix-v21' "$MAIN_TSX" && { echo "[patch-panel-hotfix-v21] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old = '''/** Returns Russian error message or null if OK. */
function validateRoomIDInput(roomId: string, carrier: string): string | null {
  const rid = normalizeRoomIDInput(roomId);
  if (!rid) return "Укажите ссылку meet или room id";
  for (const ch of rid) {
    if (ch.charCodeAt(0) > 127) return "Некорректная ссылка: используйте латинский URL";
  }
  const c = (carrier || "jitsi").trim().toLowerCase();
  if (c === "jitsi" || c === "wbstream" || c === "telemost" || c === "jazz") {
    if (rid.startsWith("http://") || rid.startsWith("https://")) {
      try {
        new URL(rid);
        return null;
      } catch {
        return "Некорректная ссылка";
      }
    }
    if (rid.includes(".") && !rid.includes(" ")) return null;
    return "Некорректная ссылка: https://meet.example.com/room или meet.example.com/room";
  }
  return null;
}'''

new = '''/** Returns Russian error message or null if OK. */
function validateRoomIDInput(roomId: string, carrier: string): string | null {
  const rid = normalizeRoomIDInput(roomId);
  if (!rid) return "Укажите room id или ссылку meet";
  for (const ch of rid) {
    if (ch.charCodeAt(0) > 127) return "Используйте латиницу и цифры";
  }
  const c = (carrier || "jitsi").trim().toLowerCase();
  // Только Jitsi требует полный URL meet; остальные провайдеры — ID комнаты.
  if (c === "jitsi") {
    if (rid.startsWith("http://") || rid.startsWith("https://")) {
      try {
        new URL(rid);
        return null;
      } catch {
        return "Некорректная ссылка Jitsi";
      }
    }
    if (rid.includes(".") && !rid.includes(" ")) return null;
    return "Некорректная ссылка: https://meet.example.com/room или meet.example.com/room";
  }
  if (c === "telemost" || c === "wbstream" || c === "jazz") {
    if (rid.startsWith("http://") || rid.startsWith("https://")) {
      return "Для этого провайдера укажите ID комнаты, а не ссылку";
    }
    if (/^[a-zA-Z0-9_-]+$/.test(rid) && rid.length >= 1 && rid.length <= 128) return null;
    return "Некорректный ID комнаты (латиница, цифры, _ и -)";
  }
  return null;
}'''

if old in t:
    t = t.replace(old, new, 1)

old_err = '''function ErrorsSummaryButton() {
  const [open, setOpen] = useState(false);
  const [autodetectOpen, setAutodetectOpen] = useState(false);
  const [items, setItems] = useState<PanelNotification[]>([]);

  useEffect(() => {
    if (!open) return;
    void fetch("/api/notifications/scan", { method: "POST" })
      .then(() => fetch("/api/notifications", { cache: "no-store" }))
      .then((r) => r.json())
      .then((b: { notifications?: PanelNotification[] }) => setItems(b.notifications ?? []));
  }, [open]);

  const issues = items.filter((n) => n.severity === "error" || n.severity === "warning");
  const errors = issues;'''

new_err = '''function ErrorsSummaryButton() {
  const [open, setOpen] = useState(false);
  const [autodetectOpen, setAutodetectOpen] = useState(false);
  const [items, setItems] = useState<PanelNotification[]>([]);

  const refreshIssues = async () => {
    try {
      await fetch("/api/notifications/scan", { method: "POST" });
      const res = await fetch("/api/notifications", { cache: "no-store" });
      if (!res.ok) return;
      const b = (await res.json()) as { notifications?: PanelNotification[] };
      setItems(b.notifications ?? []);
    } catch {
      /* ignore */
    }
  };

  useEffect(() => {
    void refreshIssues();
    const id = window.setInterval(() => void refreshIssues(), 45_000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (!open) return;
    void refreshIssues();
  }, [open]);

  const issues = items.filter((n) => n.severity === "error" || n.severity === "warning");
  const errors = issues;'''

if old_err in t:
    t = t.replace(old_err, new_err, 1)

old_bell = '''  useEffect(() => {
    void load();
    void fetch("/api/notifications/scan", { method: "POST" }).then(() => load());
    const id = window.setInterval(() => void load(), 60000);
    return () => window.clearInterval(id);
  }, []);'''

new_bell = '''  useEffect(() => {
    let intervalSec = 45;
    const tick = async () => {
      try {
        const ps = await fetch("/api/notification-settings", { cache: "no-store" });
        if (ps.ok) {
          const cfg = (await ps.json()) as { enabled?: boolean; scan_interval_sec?: number };
          if (cfg.enabled === false) return;
          if (cfg.scan_interval_sec && cfg.scan_interval_sec > 10) intervalSec = cfg.scan_interval_sec;
        }
      } catch {
        /* ignore */
      }
      await fetch("/api/notifications/scan", { method: "POST" });
      await load();
    };
    void tick();
    const id = window.setInterval(() => void tick(), intervalSec * 1000);
    return () => window.clearInterval(id);
  }, []);'''

if old_bell in t:
    t = t.replace(old_bell, new_bell, 1)

if "/* olc-panel-hotfix-v21 */" not in t:
    if "/* olc-panel-hotfix-v20 */" in t:
        t = t.replace("/* olc-panel-hotfix-v20 */", "/* olc-panel-hotfix-v20 */\n/* olc-panel-hotfix-v21 */", 1)
    else:
        t = "/* olc-panel-hotfix-v21 */\n" + t

p.write_text(t)
print("[patch-panel-hotfix-v21] ok"); print(0); raise SystemExit(0)
PY
