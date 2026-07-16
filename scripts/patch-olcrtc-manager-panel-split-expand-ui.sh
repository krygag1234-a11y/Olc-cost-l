#!/usr/bin/env bash
# Olc-cost-l frontend: кнопка «Расширить субдомены» в split-discovery.
#   Дёргает POST /api/settings/split/expand → deep авто-расширение субдоменов
#   групп (Phase 2E) + CDN (Phase 2D).
# Idempotent. Target: manager src/main.tsx. Run near end of frontend patches.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-split-expand-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. i18n строки (ru + en) ---
ru_anchor = '    splitSyncLogs: "Подтянуть CDN из логов сессии (VK и др.)",'
ru_add = ru_anchor + '''
    splitExpand: "Расширить субдомены (cert/crt.sh/CDN)",
    splitExpandRunning: "Расширение субдоменов…",
    splitExpandDone: "Субдомены и CDN добавлены в группы",'''
if 'splitExpand:' not in t and ru_anchor in t:
    t = t.replace(ru_anchor, ru_add, 1); changed = True
    print("[patch-split-expand-ui] added ru i18n")

en_anchor = '    splitSyncLogs: "Pull CDN from session logs (VK etc.)",'
en_add = en_anchor + '''
    splitExpand: "Expand subdomains (cert/crt.sh/CDN)",
    splitExpandRunning: "Expanding subdomains…",
    splitExpandDone: "Subdomains and CDN added to groups",'''
if 'splitExpand: "Expand' not in t and en_anchor in t:
    t = t.replace(en_anchor, en_add, 1); changed = True
    print("[patch-split-expand-ui] added en i18n")

# --- 2. Обработчик splitExpand (после splitSyncLogs) ---
handler_anchor = '''  const splitApplyRouting = async () => {'''
handler_add = '''  const splitExpand = async () => {
    setSaving(true);
    setSplitAnalyzeMsg(t("splitExpandRunning"));
    try {
      const res = await fetch("/api/settings/split/expand", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ force: false }),
      });
      const body = await readJsonOrText(res);
      if (!res.ok) throw new Error(String(body.error || `HTTP ${res.status}`));
      if (body.settings) setSettings(body.settings as Record<string, unknown>);
      else await reloadSettings();
      const r = (body.result || {}) as Record<string, unknown>;
      const gained = Number(r.added_domains || 0);
      setSplitAnalyzeMsg(t("splitExpandDone") + (gained ? " (+" + gained + ")" : ""));
    } catch (e) {
      setSplitAnalyzeMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const splitApplyRouting = async () => {'''
if 'const splitExpand = async' not in t and handler_anchor in t:
    t = t.replace(handler_anchor, handler_add, 1); changed = True
    print("[patch-split-expand-ui] added splitExpand handler")

# --- 3. Кнопка (после splitSyncLogs-кнопки) ---
btn_anchor = '''                    <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={saving} onClick={() => void splitSyncLogs()}>
                      {t("splitSyncLogs")}
                    </button>'''
btn_add = btn_anchor + '''
                    <button type="button" className="rounded border border-border px-2 py-1 text-xs hover:bg-muted" disabled={saving} onClick={() => void splitExpand()}>
                      {t("splitExpand")}
                    </button>'''
if 'void splitExpand()' not in t and btn_anchor in t:
    t = t.replace(btn_anchor, btn_add, 1); changed = True
    print("[patch-split-expand-ui] added expand button")

# --- 4. Подсветка «успех» для splitExpandDone ---
hl_anchor = 'splitAnalyzeMsg === t("splitApplyRoutingDone") ?'
if 'startsWith(t("splitExpandDone"))' not in t and hl_anchor in t:
    t = t.replace(hl_anchor, 'splitAnalyzeMsg.startsWith(t("splitExpandDone")) || splitAnalyzeMsg === t("splitApplyRoutingDone") ?', 1)
    changed = True
    print("[patch-split-expand-ui] added success highlight for expand")

if changed:
    f.write_text(t)
    print("[patch-split-expand-ui] OK: main.tsx updated")
else:
    print("[patch-split-expand-ui] no changes (idempotent)")
PY
