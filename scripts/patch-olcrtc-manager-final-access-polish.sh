#!/usr/bin/env bash
set -euo pipefail

MAIN_GO="${1:?usage: $0 <main.go> <main.tsx>}"
MAIN_TSX="${2:?usage: $0 <main.go> <main.tsx>}"

python3 - "$MAIN_GO" "$MAIN_TSX" <<'PY'
from pathlib import Path
import re, sys

gp, tp = Path(sys.argv[1]), Path(sys.argv[2])
go, tsx = gp.read_text(), tp.read_text()

def one(text, old, new, label):
    if old in text:
        if text.count(old) != 1:
            raise SystemExit(f"[final-access] {label}: expected 1, got {text.count(old)}")
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f"[final-access] {label}: anchor missing")

# Persistent labels survive moves/removals.  They are garbage-collected after
# 30 days only when absent from every allow/ban list and inactive in both logs.
if 'type olcDeviceLabelState struct {' not in go:
    go = one(go, 'type olcAccessControl struct {', '''type olcDeviceLabelState struct {
	Label     string `json:"label"`
	UpdatedAt string `json:"updated_at,omitempty"`
	LastSeen  string `json:"last_seen,omitempty"`
}

type olcAccessControl struct {''', 'label state type')
    go, n = re.subn(
        r'(?m)^(\s*AllowedHWIDs\s+\[\]string\s+`json:"allowed_hwids,omitempty"`.*)$',
        '\tDeviceLabels map[string]olcDeviceLabelState `json:"device_labels,omitempty"`\n' + r'\1',
        go, count=1,
    )
    if n != 1: raise SystemExit('[final-access] label state field: anchor missing')
    go = one(go, '\tAllowed  bool   `json:"allowed"`', '\tAllowed  bool   `json:"allowed"`\n\tLabel    string `json:"label,omitempty"`', 'attempt label')
    go = one(go, '\tDevice       string `json:"device"`', '\tDevice       string `json:"device"`\n\tLabel        string `json:"label,omitempty"`', 'connection label')

    helper = r'''func olcAccessSyncDeviceLabels(ac *olcAccessControl) {
	if ac == nil { return }
	if ac.DeviceLabels == nil { ac.DeviceLabels = map[string]olcDeviceLabelState{} }
	now := time.Now().UTC()
	member := map[string]bool{}
	lists := [][]olcAllowedDevice{ac.Devices, ac.Ban, ac.ConnDevices, ac.ConnBan}
	for _, cc := range ac.Clients {
		if cc != nil { lists = append(lists, cc.Allow, cc.Ban, cc.ConnAllow, cc.ConnBan) }
	}
	for _, list := range lists {
		for _, d := range list {
			h := strings.ToLower(strings.TrimSpace(d.HWID)); if h == "" { continue }
			member[h] = true
			if label := strings.TrimSpace(d.Label); label != "" {
				cur := ac.DeviceLabels[h]
				if cur.Label != label { cur.Label, cur.UpdatedAt = label, now.Format(time.RFC3339) }
				if cur.UpdatedAt == "" { cur.UpdatedAt = now.Format(time.RFC3339) }
				ac.DeviceLabels[h] = cur
			}
		}
	}
	hydrate := func(list []olcAllowedDevice) {
		for i := range list { if list[i].Label == "" { list[i].Label = ac.DeviceLabels[strings.ToLower(strings.TrimSpace(list[i].HWID))].Label } }
	}
	hydrate(ac.Devices); hydrate(ac.Ban); hydrate(ac.ConnDevices); hydrate(ac.ConnBan)
	for _, cc := range ac.Clients { if cc != nil { hydrate(cc.Allow); hydrate(cc.Ban); hydrate(cc.ConnAllow); hydrate(cc.ConnBan) } }
	lastSeen := map[string]string{}
	for _, a := range olcAccessLoadAttempts() {
		h := strings.ToLower(strings.TrimSpace(a.HWID)); if h != "" && a.TS > lastSeen[h] { lastSeen[h] = a.TS }
	}
	var cj struct { Records []*olcConnRecord `json:"records"` }
	if data, err := os.ReadFile(olcConnJournalPath); err == nil { _ = json.Unmarshal(data, &cj) }
	for _, rec := range cj.Records { if rec != nil { h := strings.ToLower(strings.TrimSpace(rec.Device)); if h != "" && rec.Last > lastSeen[h] { lastSeen[h] = rec.Last } } }
	cutoff := now.Add(-30 * 24 * time.Hour)
	for h, entry := range ac.DeviceLabels {
		if seen := lastSeen[h]; seen > entry.LastSeen { entry.LastSeen = seen; ac.DeviceLabels[h] = entry }
		if member[h] { continue }
		ref := entry.LastSeen; if entry.UpdatedAt > ref { ref = entry.UpdatedAt }
		when, err := time.Parse(time.RFC3339, ref)
		if ref == "" || (err == nil && when.Before(cutoff)) { delete(ac.DeviceLabels, h) }
	}
}

func olcAccessLabel(ac olcAccessControl, hwid string) string {
	return ac.DeviceLabels[strings.ToLower(strings.TrimSpace(hwid))].Label
}

'''
    go = one(go, 'var olcDeviceLineRe = regexp.MustCompile(`device=([^\\s)]+)`)\n\nfunc olcAccessSave',
        'var olcDeviceLineRe = regexp.MustCompile(`device=([^\\s)]+)`)\n\n' + helper + 'func olcAccessSave', 'label helpers')
    go = one(go, 'func olcAccessSave(ac olcAccessControl) error {\n\tac.UpdatedAt',
        'func olcAccessSave(ac olcAccessControl) error {\n\tolcAccessSyncDeviceLabels(&ac)\n\tac.UpdatedAt', 'label sync save')
    go = one(go, '\tif ac.Clients == nil {\n\t\tac.Clients = map[string]*olcClientAccess{}\n\t}\n\treturn ac',
        '\tif ac.Clients == nil {\n\t\tac.Clients = map[string]*olcClientAccess{}\n\t}\n\tolcAccessSyncDeviceLabels(&ac)\n\treturn ac', 'label sync load')

    go = one(go, 'func accessAttemptsHandler(w http.ResponseWriter, r *http.Request) {\n\twriteJSON(w, map[string]any{"attempts": olcAccessLoadAttempts()})\n}',
        '''func accessAttemptsHandler(w http.ResponseWriter, r *http.Request) {
	list := olcAccessLoadAttempts(); ac := olcAccessLoad()
	for i := range list { list[i].Label = olcAccessLabel(ac, list[i].HWID) }
	writeJSON(w, map[string]any{"attempts": list})
}''', 'attempt labels response')
    go = one(go, '\tcid := strings.TrimSpace(r.URL.Query().Get("client_id"))\n\tif cid != "" {',
        '\tcid := strings.TrimSpace(r.URL.Query().Get("client_id"))\n\thwid := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("hwid")))\n\tif hwid != "" {\n\t\tkept := []olcAccessAttempt{}\n\t\tfor _, a := range olcAccessLoadAttempts() { if strings.ToLower(strings.TrimSpace(a.HWID)) != hwid { kept = append(kept, a) } }\n\t\t_olcAccessWriteAttempts(kept)\n\t} else if cid != "" {', 'clear attempt by hwid')

    clear_old = '''		if cid != "" {
			//'''
    clear_new = '''		hwid := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("hwid")))
		if hwid != "" {
			kept := olcConnJournal[:0]
			for _, rec := range olcConnJournal { if strings.ToLower(strings.TrimSpace(rec.Device)) != hwid { kept = append(kept, rec) } }
			olcConnJournal = kept
		} else if cid != "" {
			//'''
    if clear_old not in go: raise SystemExit('[final-access] connection clear anchor missing')
    go = go.replace(clear_old, clear_new, 1)
    go = one(go, '\tlist := make([]olcConnRecord, 0, len(sorted))\n\tfor _, rec := range sorted {\n\t\tlist = append(list, *rec)\n\t}',
        '\tlist := make([]olcConnRecord, 0, len(sorted)); ac := olcAccessLoad()\n\tfor _, rec := range sorted {\n\t\tcopy := *rec; copy.Label = olcAccessLabel(ac, copy.Device); list = append(list, copy)\n\t}', 'connection labels response')

# Plain Enter finishes every real input field; modifiers and composition do not.
if 'olc-plain-enter-blur' not in tsx:
    tsx = one(tsx, 'function App() {\n  const { t, lang, setLang } = usePanelLang();', '''function App() {
  useEffect(() => {
    const finishInput = (e: KeyboardEvent) => {
      if (e.key !== "Enter" || e.shiftKey || e.ctrlKey || e.altKey || e.metaKey || e.isComposing) return;
      const el = e.target;
      if (!(el instanceof HTMLInputElement)) return;
      if (["button", "submit", "reset", "checkbox", "radio", "file", "range", "color"].includes(el.type)) return;
      e.preventDefault();
      el.blur();
    };
    document.addEventListener("keydown", finishInput, true); // olc-plain-enter-blur
    return () => document.removeEventListener("keydown", finishInput, true);
  }, []);
  const { t, lang, setLang } = usePanelLang();''', 'plain Enter handler')

# API support for resetting old red/orange counters when a device becomes allowed.
if 'olcClearDeviceHistory' not in tsx:
    tsx = one(tsx, 'function AccessControlSection() {', '''const olcClearDeviceHistory = (hwid: string) => {
  const q = encodeURIComponent((hwid || "").trim()); if (!q) return;
  void Promise.all([
    fetch(`/api/access/attempts/clear?hwid=${q}`, { method: "POST" }),
    fetch(`/api/access/connections?clear=1&hwid=${q}`),
  ]);
};

function AccessControlSection() {''', 'history reset helper')
    # Direct and confirmed transitions in both global and selective sections.
    # These anchors intentionally match the output of the earlier device-label
    # patch (namedGlobalDevice/namedClientDevice), so a partial callback rewrite
    # cannot leave invalid TSX behind.
    tsx = one(tsx,
        'run: () => void saveSettings({ conn_ban: dropH(connBan, h), conn_devices: [...connDevices, namedGlobalDevice(h)] })',
        'run: () => { olcClearDeviceHistory(h); void saveSettings({ conn_ban: dropH(connBan, h), conn_devices: [...connDevices, namedGlobalDevice(h)] }); }',
        'global confirmed connection allow')
    tsx = one(tsx,
        'void saveSettings({ conn_devices: [...connDevices, namedGlobalDevice(h)] });',
        'olcClearDeviceHistory(h); void saveSettings({ conn_devices: [...connDevices, namedGlobalDevice(h)] });',
        'global direct connection allow')
    tsx = one(tsx,
        'run: () => { setNewHwid(""); void saveSettings({ ban: dropH(ban, h), devices: [...devices, namedGlobalDevice(h)] }); }',
        'run: () => { setNewHwid(""); olcClearDeviceHistory(h); void saveSettings({ ban: dropH(ban, h), devices: [...devices, namedGlobalDevice(h)] }); }',
        'global confirmed subscription allow')
    tsx = one(tsx,
        'setNewHwid("");\n    await saveSettings({ devices: [...devices, namedGlobalDevice(h)] });',
        'setNewHwid("");\n    olcClearDeviceHistory(h); await saveSettings({ devices: [...devices, namedGlobalDevice(h)] });',
        'global direct subscription allow')
    tsx = one(tsx,
        'run: () => void save({ conn_ban: dropHwid(connBan, h), conn_allow: [...connAllow, namedClientDevice(h)] })',
        'run: () => { olcClearDeviceHistory(h); void save({ conn_ban: dropHwid(connBan, h), conn_allow: [...connAllow, namedClientDevice(h)] }); }',
        'selective confirmed connection allow')
    tsx = one(tsx,
        'void save({ conn_allow: [...connAllow, namedClientDevice(h)] });',
        'olcClearDeviceHistory(h); void save({ conn_allow: [...connAllow, namedClientDevice(h)] });',
        'selective direct connection allow')
    tsx = one(tsx,
        'run: () => { setNewAllow(""); void save({ ban: dropHwid(ban, h), allow: [...allow, namedClientDevice(h)] }); }',
        'run: () => { setNewAllow(""); olcClearDeviceHistory(h); void save({ ban: dropHwid(ban, h), allow: [...allow, namedClientDevice(h)] }); }',
        'selective confirmed subscription allow')
    tsx = one(tsx,
        'setNewAllow(""); void save({ allow: [...allow, namedClientDevice(h)] });',
        'setNewAllow(""); olcClearDeviceHistory(h); void save({ allow: [...allow, namedClientDevice(h)] });',
        'selective direct subscription allow')

# Names are returned with log records, so they remain visible even when a device
# currently lives only in a ban list or in the 30-day retained registry.
tsx = tsx.replace('{knownDev?.label?.trim() || hwid ||', '{a.label?.trim() || knownDev?.label?.trim() || hwid ||')
tsx = tsx.replace('{knownDev?.label?.trim() && <span', '{(a.label?.trim() || knownDev?.label?.trim()) && <span')
tsx = tsx.replace('dev: gdev,\n              rows:', 'dev: gdev,\n              label: rows.map((r: any) => String(r.label || "").trim()).find(Boolean) || "",\n              rows:')
tsx = tsx.replace('▷ {dev || "—"}', '▷ {g.label || dev || "—"}')

# Allowed is a full blue status, not stale denied/kicked counters.  Removing it
# reveals only attempts made after the allow transition (history was reset).
tsx = tsx.replace('{known && <span className="text-sky-400">✓</span>}', '{known && <span className="ml-1 rounded border border-sky-500/40 bg-sky-500/10 px-1 text-sky-300">Разрешённый</span>}')
tsx = tsx.replace('{g.count > 0 && <span', '{!known && g.count > 0 && <span')
tsx = tsx.replace('{g.denied > 0 && <span', '{!known && g.denied > 0 && <span')
tsx = tsx.replace('{g.kicked > 0 && <span', '{!known && g.kicked > 0 && <span')

# Both global and selective connection journals wrap long values.
tsx = tsx.replace('className="grid max-h-56 gap-1 overflow-y-auto rounded border border-border bg-background p-2"', 'className="grid max-h-56 gap-1 overflow-x-hidden overflow-y-auto rounded border border-border bg-background p-2"')
tsx = tsx.replace('className="grid max-h-40 gap-1 overflow-y-auto rounded border border-border bg-background p-2"', 'className="grid max-h-40 gap-1 overflow-x-hidden overflow-y-auto rounded border border-border bg-background p-2"')
tsx = tsx.replace('<div className="truncate font-mono">▷ {g.label || dev || "—"}', '<div className="break-all font-mono">▷ {g.label || dev || "—"}')
tsx = tsx.replace('<div className="truncate text-muted-foreground">инстансов:', '<div className="break-words text-muted-foreground">инстансов:')

# Explain the expected reconnect delay in both connection-control sections.
note = 'Изменения доступа во время активного подключения применяются сразу, но восстановление туннеля после переключения может занять некоторое время. При проверке смотрите логи нужного инстанса.'
anchor = '<div className="text-[11px] text-muted-foreground">Устройства (device), реально подключавшиеся к инстансам'
tsx = tsx.replace(anchor, f'<div className="rounded border border-sky-500/25 bg-sky-500/5 px-2 py-1 text-[10px] text-sky-200">{note}</div>\n            {anchor}')
selective_anchor = '<div className="text-xs font-semibold text-foreground">🔌 Журнал подключений (эта подписка)</div>'
tsx = tsx.replace(selective_anchor, selective_anchor + f'\n              <div className="rounded border border-sky-500/25 bg-sky-500/5 px-2 py-1 text-[10px] text-sky-200">{note}</div>')

if tsx.count('olc-plain-enter-blur') != 1: raise SystemExit('[final-access] plain Enter guard missing')
if tsx.count('Разрешённый</span>') != 2: raise SystemExit(f'[final-access] allowed badges: {tsx.count("Разрешённый</span>")}')
if tsx.count(note) != 2: raise SystemExit(f'[final-access] stabilization notes: {tsx.count(note)}')

gp.write_text(go); tp.write_text(tsx)
print('[final-access] labels TTL, log cards, Enter and stabilization notes applied')
PY
