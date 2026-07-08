#!/usr/bin/env bash
# Phase 2C Step 3: Unify 3 split routing buttons into one "Apply" with progress

set -e
TARGET="${1:-src/main.tsx}"

if ! [ -f "$TARGET" ]; then
  echo "[split-2c-step3] target not found: $TARGET" >&2
  exit 1
fi

# Idempotency: check if already patched
if grep -q "splitApplyAll" "$TARGET" 2>/dev/null; then
  echo "[split-2c-step3] already applied" >&2
  exit 0
fi

python3 - "$TARGET" <<'PYSCRIPT'
import sys, re

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    t = f.read()

# Anchor 1: Add splitApplyAll function after splitApplyRouting
anchor_func = '''  const splitApplyRouting = async () => {
    setSaving(true);
    setSplitAnalyzeMsg("");
    try {
      const res = await fetch("/api/settings/split/apply-routing", { method: "POST" });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      setSplitAnalyzeMsg(t("splitApplyRoutingDone"));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
      window.setTimeout(() => setSplitAnalyzeMsg((m) => (m === t("splitApplyRoutingDone") ? "" : m)), 8000);
    }
  };'''

new_func = '''  const splitApplyRouting = async () => {
    setSaving(true);
    setSplitAnalyzeMsg("");
    try {
      const res = await fetch("/api/settings/split/apply-routing", { method: "POST" });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      setSplitAnalyzeMsg(t("splitApplyRoutingDone"));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
      window.setTimeout(() => setSplitAnalyzeMsg((m) => (m === t("splitApplyRoutingDone") ? "" : m)), 8000);
    }
  };

  const splitApplyAll = async () => {
    setSaving(true);
    setSplitAnalyzeMsg("Синхронизация конфига...");
    try {
      const res1 = await fetch("/api/settings/split/sync-config", { method: "POST" });
      const body1 = await readJsonOrText(res1);
      if (!res1.ok) throw new Error(`Sync config: ${body1.error || res1.status}`);
      if (body1.settings) setSettings(body1.settings as Record<string, unknown>);
      else await reloadSettings();

      setSplitAnalyzeMsg("Синхронизация логов...");
      const res2 = await fetch("/api/settings/split/sync-logs", { method: "POST" });
      const body2 = await readJsonOrText(res2);
      if (!res2.ok) throw new Error(`Sync logs: ${body2.error || res2.status}`);
      if (body2.settings) setSettings(body2.settings as Record<string, unknown>);
      else await reloadSettings();

      setSplitAnalyzeMsg("Применение роутинга...");
      const res3 = await fetch("/api/settings/split/apply-routing", { method: "POST" });
      const body3 = await readJsonOrText(res3);
      if (!res3.ok) throw new Error(`Apply routing: ${body3.error || res3.status}`);

      setSplitAnalyzeMsg("✓ Все изменения применены");
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
      window.setTimeout(() => setSplitAnalyzeMsg((m) => (m === "✓ Все изменения применены" ? "" : m)), 8000);
    }
  };'''

if anchor_func not in t:
    print("[split-2c-step3] anchor not found: splitApplyRouting function", file=sys.stderr)
    sys.exit(1)

t = t.replace(anchor_func, new_func)

# Anchor 2: Replace 3-button section with single unified button
old_section = '''                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="font-medium">{t("splitGlobalSyncTitle")}</div>
                      <p className="text-xs text-muted-foreground">{t("splitGlobalSyncHelp")}</p>
                    </div>
                    <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={saving} onClick={() => void splitSyncConfig()}>
                      {t("splitSyncConfig")}
                    </button>
                    <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={saving} onClick={() => void splitSyncLogs()}>
                      {t("splitSyncLogs")}
                    </button>
                    <button type="button" className="rounded border border-primary px-2 py-1 text-xs text-primary" disabled={saving} onClick={() => void splitApplyRouting()}>
                      {t("splitApplyRouting")}
                    </button>
                  </div>
                  <p className="text-[10px] text-muted-foreground">{t("splitRestartHint")}</p>
                </section>'''

new_section = '''                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <div>
                      <div className="font-medium">Применить изменения</div>
                      <p className="text-xs text-muted-foreground">Синхронизирует конфиг, логи и применяет роутинг</p>
                    </div>
                    <button
                      type="button"
                      className="rounded border border-primary bg-primary/10 px-4 py-2 text-sm font-medium text-primary hover:bg-primary/20 disabled:opacity-50"
                      disabled={saving}
                      onClick={() => void splitApplyAll()}
                    >
                      Применить
                    </button>
                  </div>
                  {splitAnalyzeMsg && (
                    <p className={`text-xs ${splitAnalyzeMsg.startsWith("✓") ? "text-emerald-400" : splitAnalyzeMsg.includes("...") ? "text-blue-400" : "text-red-400"}`}>
                      {splitAnalyzeMsg}
                    </p>
                  )}
                  <p className="text-[10px] text-muted-foreground">{t("splitRestartHint")}</p>
                </section>'''

if old_section not in t:
    print("[split-2c-step3] anchor not found: splitGlobalSyncTitle section", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_section, new_section)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(t)

print("[split-2c-step3] unify 3 buttons into one 'Apply' with progress: ok", file=sys.stderr)
PYSCRIPT
