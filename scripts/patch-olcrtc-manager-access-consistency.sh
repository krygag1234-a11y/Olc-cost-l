#!/usr/bin/env bash
set -euo pipefail

main_go=${1:?usage: $0 <main.go> <main.tsx>}
main_tsx=${2:?usage: $0 <main.go> <main.tsx>}

python3 - "$main_go" "$main_tsx" <<'PY'
from pathlib import Path
import re, sys

go_path, tsx_path = map(Path, sys.argv[1:3])
go = go_path.read_text()
tsx = tsx_path.read_text()

def one(text, old, new, label):
    n = text.count(old)
    if n == 1:
        return text.replace(old, new, 1)
    if n == 0 and new in text:
        return text
    raise SystemExit(f"[access-consistency] {label}: expected one anchor, got {n}")

# The attempt journal is a separate file and keeps its own mutex.
go = one(go, 'var olcAccessMu sync.Mutex',
'''var olcAccessMu sync.Mutex
var olcAccessConfigMu sync.Mutex''', 'config mutex')
go = one(go, '''\t\tcur := olcAccessLoad()
\t\tif in.Enabled != nil {''', '''\t\tolcAccessConfigMu.Lock()
\t\tdefer olcAccessConfigMu.Unlock()
\t\tcur := olcAccessLoad()
\t\tif in.Enabled != nil {''', 'global transaction')
go = one(go, '''\tid := strings.TrimSpace(body.ClientID)
\tif id == "" {
\t\twriteJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "client_id required"})
\t\treturn
\t}
\tac := olcAccessLoad()''', '''\tid := strings.TrimSpace(body.ClientID)
\tif id == "" {
\t\twriteJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "client_id required"})
\t\treturn
\t}
\tolcAccessConfigMu.Lock()
\tdefer olcAccessConfigMu.Unlock()
\tac := olcAccessLoad()''', 'selective transaction')

# A fresh handshake attempt means the client is actively retrying that
# instance.  Treat it as busy for two minutes even when PeerSummary is zero.
go = one(go, '''\treturn out
}

// olcKeyRotationOnFetch''', '''\treturn out
}

func olcRecentConnectionAttempts(window time.Duration) map[string]int {
\tout := map[string]int{}
\tif panelSupervisor == nil { return out }
\tcutoff := time.Now().UTC().Add(-window)
\tpanelSupervisor.mu.RLock()
\tprocs := make(map[string]*process, len(panelSupervisor.processes))
\tfor key, p := range panelSupervisor.processes { procs[key] = p }
\tpanelSupervisor.mu.RUnlock()
\tfor key, p := range procs {
\t\tif p == nil || p.logs == nil { continue }
\t\tfor _, ln := range p.logs.Snapshot() {
\t\t\tif !strings.Contains(ln.Line, "olc-access: conn attempt") { continue }
\t\t\tts, err := time.Parse(time.RFC3339Nano, ln.Time)
\t\t\tif err == nil && !ts.Before(cutoff) { out[key]++ }
\t\t}
\t}
\treturn out
}

// olcKeyRotationOnFetch''', 'recent connection attempts helper')
go = one(go, '''\tpeers := olcInstancePeerCount()
\tchanged := false''', '''\tpeers := olcInstancePeerCount()
\trecentAttempts := olcRecentConnectionAttempts(2 * time.Minute)
\tchanged := false''', 'recent attempts snapshot')
go = one(go, '''\t\t\tif peers[key] > 0 {
\t\t\t\tskipped++
\t\t\t\tlog.Printf("olc-keyrot: skip busy inst=%s peers=%d (defer to next round)", key, peers[key])
\t\t\t\tcontinue
\t\t\t}''', '''\t\t\tif peers[key] > 0 || recentAttempts[key] > 0 {
\t\t\t\tskipped++
\t\t\t\tlog.Printf("olc-keyrot: skip busy inst=%s peers=%d recent_attempts=%d (defer to next round)", key, peers[key], recentAttempts[key])
\t\t\t\tcontinue
\t\t\t}''', 'rotation busy gate')

# Both modals remain clickable while saving, but writes are serialized and old
# responses are forbidden from rolling newer optimistic state back.
busy = '  const [busy, setBusy] = useState(false);'
if tsx.count(busy) == 2:
    tsx = tsx.replace(busy, busy + '''
  const saveQueueRef = useRef<Promise<void>>(Promise.resolve());
  const saveVersionRef = useRef(0);
  const pendingSavesRef = useRef(0);''')
elif tsx.count('const saveQueueRef = useRef<Promise<void>>(Promise.resolve());') != 2:
    raise SystemExit('[access-consistency] busy anchors')

global_re = re.compile(r'''  const saveSettings = async \(next: \{.*?\n  \};\n  // .*?Конфликт''', re.S)
global_new = '''  const saveSettings = (next: { enabled?: boolean; mode?: string; devices?: any[]; ban?: any[]; ban_no_hwid?: boolean; enforce_connections?: boolean; conn_devices?: any[]; conn_ban?: any[]; allowed_ips?: any[]; ban_ips?: any[]; conn_scope?: string; conn_instances?: string[] }) => {
    const version = ++saveVersionRef.current;
    pendingSavesRef.current += 1; setBusy(true); setMsg(null);
    const run = async () => {
      try {
        const res = await fetch("/api/access/settings", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...next }) });
        const b = await res.json(); if (!res.ok) throw new Error(b.error || ("HTTP " + res.status));
        if (version === saveVersionRef.current) {
          setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : "monitor");
          setDevices(Array.isArray(b.devices) ? b.devices : []); setBan(Array.isArray(b.ban) ? b.ban : []);
          setBanNoHwid(!!b.ban_no_hwid); setEnforceConns(!!b.enforce_connections);
          setConnDevices(Array.isArray(b.conn_devices) ? b.conn_devices : []); setConnBan(Array.isArray(b.conn_ban) ? b.conn_ban : []);
          setConnScope(b.conn_scope === "selective" ? "selective" : "all"); setConnInstances(Array.isArray(b.conn_instances) ? b.conn_instances : []);
          setAllowedIps(normIps(b.allowed_ips)); setBanIps(normIps(b.ban_ips));
        }
        try { window.dispatchEvent(new CustomEvent("olc-access-saved", { detail: { enabled: !!b.enabled } })); } catch { /* ignore */ }
      } catch (e: any) { if (version === saveVersionRef.current) setMsg("Ошибка: " + (e?.message || String(e))); }
      finally { pendingSavesRef.current -= 1; if (pendingSavesRef.current === 0) setBusy(false); }
    };
    saveQueueRef.current = saveQueueRef.current.then(run, run); return saveQueueRef.current;
  };
  // ── Конфликт'''
if tsx.count('pendingSavesRef.current += 1; setBusy(true); setMsg(null);') == 0:
    tsx, n = global_re.subn(global_new, tsx, count=1)
    if n != 1: raise SystemExit(f'[access-consistency] global save: {n}')

client_re = re.compile(r'''  const save = async \(next\?: \{.*?\n  \};\n  // .*?Конфликт''', re.S)
client_new = '''  const save = (next?: { mode?: string; allow?: Dev[]; ban?: Dev[]; allow_ips?: any[]; ban_ips?: any[]; ban_no_hwid?: boolean; conn_allow?: Dev[]; conn_ban?: Dev[]; conn_enforce?: boolean; conn_scope?: string; conn_instances?: string[] }) => {
    const version = ++saveVersionRef.current;
    pendingSavesRef.current += 1; setBusy(true); setMsg(null);
    const run = async () => {
      try {
        const r = await fetch("/api/access/client", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ client_id: clientId, ...(next || {}) }) });
        const b = await r.json(); if (!r.ok) throw new Error(b.error || ("HTTP " + r.status));
        const cc = (b.clients || {})[clientId] || {};
        if (version === saveVersionRef.current) {
          setMode(cc.mode === "enforce" ? "enforce" : "off"); setAllow(Array.isArray(cc.allow) ? cc.allow : []); setBan(Array.isArray(cc.ban) ? cc.ban : []);
          setConnAllow(Array.isArray(cc.conn_allow) ? cc.conn_allow : []); setConnBan(Array.isArray(cc.conn_ban) ? cc.conn_ban : []);
          setAllowIps(normIps(cc.allow_ips)); setBanIps(normIps(cc.ban_ips)); setBanNoHwid(!!cc.ban_no_hwid);
          setConnEnforce(!!cc.conn_enforce); setConnScope(cc.conn_scope === "selective" ? "selective" : "all"); setConnInstances(Array.isArray(cc.conn_instances) ? cc.conn_instances : []);
        }
        try { window.dispatchEvent(new CustomEvent("olc-access-saved", { detail: {} })); } catch { /* ignore */ }
      } catch (e: any) { if (version === saveVersionRef.current) setMsg("Ошибка: " + (e?.message || String(e))); }
      finally { pendingSavesRef.current -= 1; if (pendingSavesRef.current === 0) setBusy(false); }
    };
    saveQueueRef.current = saveQueueRef.current.then(run, run); return saveQueueRef.current;
  };
  // ── Конфликт'''
if tsx.count('pendingSavesRef.current += 1; setBusy(true); setMsg(null);') == 1:
    tsx, n = client_re.subn(client_new, tsx, count=1)
    if n != 1: raise SystemExit(f'[access-consistency] client save: {n}')

tsx = one(tsx, '  const dropH = (list: Array<any>, h: string) => (list || []).filter((d) => (d.hwid || "").toLowerCase() !== (h || "").toLowerCase());', '''  const dropH = (list: Array<any>, h: string) => (list || []).filter((d) => (d.hwid || "").toLowerCase() !== (h || "").toLowerCase());
  const namedGlobalDevice = (h: string) => { const d = [...devices, ...ban, ...connDevices, ...connBan].find((x) => (x.hwid || "").toLowerCase() === h.toLowerCase()); return { hwid: h, ...(d?.label?.trim() ? { label: d.label.trim() } : {}), enabled: true }; };
  const saveGlobalLabel = (h: string, label: string) => { const patch = (xs: any[]) => xs.map((x) => (x.hwid || "").toLowerCase() === h.toLowerCase() ? { ...x, label } : x); const nd=patch(devices), nb=patch(ban), nc=patch(connDevices), ncb=patch(connBan); setDevices(nd); setBan(nb); setConnDevices(nc); setConnBan(ncb); void saveSettings({ devices: nd, ban: nb, conn_devices: nc, conn_ban: ncb }); };''', 'global label helpers')
tsx = one(tsx, '  const dropHwid = (list: Dev[], h: string) => list.filter((d) => (d.hwid || "").toLowerCase() !== (h || "").toLowerCase());', '''  const dropHwid = (list: Dev[], h: string) => list.filter((d) => (d.hwid || "").toLowerCase() !== (h || "").toLowerCase());
  const namedClientDevice = (h: string) => { const d = [...allow, ...ban, ...connAllow, ...connBan].find((x) => (x.hwid || "").toLowerCase() === h.toLowerCase()); return { hwid: h, ...(d?.label?.trim() ? { label: d.label.trim() } : {}), enabled: true }; };
  const saveClientLabel = (h: string, label: string) => { const patch = (xs: Dev[]) => xs.map((x) => (x.hwid || "").toLowerCase() === h.toLowerCase() ? { ...x, label } : x); const na=patch(allow), nb=patch(ban), nc=patch(connAllow), ncb=patch(connBan); setAllow(na); setBan(nb); setConnAllow(nc); setConnBan(ncb); void save({ allow: na, ban: nb, conn_allow: nc, conn_ban: ncb }); };''', 'client label helpers')

g0, c0, c1 = tsx.index('function AccessControlSection()'), tsx.index('function ClientAccessModal('), tsx.index('function ComponentSettingsModal(')
g, c = tsx[g0:c0], tsx[c0:c1]
g = g.replace('{ hwid: h, enabled: true }', 'namedGlobalDevice(h)')
c = c.replace('{ hwid: h, enabled: true }', 'namedClientDevice(h)')
# Keep every global UI mutation on the same ordered /settings queue.  The old
# per-item endpoints bypassed it and could still race a ban/mode save.
g, n = re.subn(r'''  const setDevice = async \(hwid: string, patch: \{ label\?: string; enabled\?: boolean \}\) => \{.*?\n  \};''', '''  const setDevice = (hwid: string, patch: { label?: string; enabled?: boolean }) => { const nx = devices.map((d) => d.hwid === hwid ? { ...d, ...patch } : d); setDevices(nx); void saveSettings({ devices: nx }); };''', g, count=1, flags=re.S)
if n != 1: raise SystemExit(f'[access-consistency] setDevice queue: {n}')
g, n = re.subn(r'''  const remove = async \(hwid: string\) => \{.*?\n  \};''', '''  const remove = (hwid: string) => { const nx = devices.filter((d) => d.hwid !== hwid); setDevices(nx); void saveSettings({ devices: nx }); };''', g, count=1, flags=re.S)
if n != 1: raise SystemExit(f'[access-consistency] remove queue: {n}')
g, n = re.subn(r'''  const removeIp = async \(ip: string\) => \{.*?\n  \};''', '''  const removeIp = (ip: string) => { const nx = allowedIps.filter((x) => x.ip !== ip); setAllowedIps(nx); void saveSettings({ allowed_ips: nx }); };''', g, count=1, flags=re.S)
if n != 1: raise SystemExit(f'[access-consistency] removeIp queue: {n}')
g = re.sub(r'onBlur=\{\(e\) => \{ if \(\(e\.target\.value \|\| ""\) !== \(d\.label \|\| ""\)\) (?:void )?(?:setDevice|setConnDevice)\(d\.hwid, \{ label: e\.target\.value \}\); \}\} />', 'onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) saveGlobalLabel(d.hwid, e.target.value); }} />', g)

label_input = '''<input className="h-7 w-28 shrink-0 rounded border border-border bg-card px-1 text-[11px] text-foreground outline-none focus:border-primary"
                      placeholder="имя" defaultValue={d.label || ""}
                      onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) saveGlobalLabel(d.hwid, e.target.value); }} />'''
for color in ('text-red-300', 'text-orange-300'):
    pat = re.compile(r'(\s+)(<span className=\{`min-w-0 flex-1 truncate font-mono \$\{d\.enabled === false \? "text-muted-foreground line-through" : "' + re.escape(color) + r'"\}`\}>\{d\.hwid\}</span>)')
    g, n = pat.subn(lambda m: m.group(1) + label_input + m.group(1) + m.group(2), g, count=1)
    if n != 1: raise SystemExit(f'[access-consistency] global banned label {color}: {n}')

c = c.replace('onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) onLabel(e.target.value); }} />', 'onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }} onBlur={(e) => { if ((e.target.value || "") !== (d.label || "")) onLabel(e.target.value); }} />')
c = re.sub(r', \(label\) => void save\(\{ (?:allow|conn_allow): .*?\}\)\)\}', ', (label) => saveClientLabel(d.hwid, label))}', c)
for name in ('allow', 'ban', 'connAllow', 'connBan'):
    line_re = re.compile(rf'\{{{name}\.map\(\(d\) => devRow\((.*?)\)\)\}}')
    def add_label(m):
        body = m.group(1)
        if 'saveClientLabel' in body: return m.group(0)
        return '{' + name + '.map((d) => devRow(' + body + ', (label) => saveClientLabel(d.hwid, label)))}'
    c, n = line_re.subn(add_label, c, count=1)
    if n != 1: raise SystemExit(f'[access-consistency] client label row {name}: {n}')

tsx = tsx[:g0] + g + c + tsx[c1:]

# The selective inline journals must wrap long HWID/UA/location strings.
tsx = tsx.replace('className="grid max-h-40 gap-1 overflow-y-auto rounded border border-border bg-background p-2"', 'className="grid max-h-40 gap-1 overflow-x-hidden overflow-y-auto rounded border border-border bg-background p-2"')
tsx = tsx.replace('className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]"', 'className="flex min-w-0 flex-wrap items-start justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]"')
tsx = tsx.replace('className="truncate font-mono"', 'className="break-all font-mono"')
tsx = tsx.replace('className="truncate text-muted-foreground"', 'className="break-words text-muted-foreground"')

if tsx.count('const saveQueueRef = useRef<Promise<void>>(Promise.resolve());') != 2: raise SystemExit('[access-consistency] expected two queues')
if tsx.count('onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}') < 4: raise SystemExit('[access-consistency] Enter coverage incomplete')

go_path.write_text(go)
tsx_path.write_text(tsx)
print('[access-consistency] mutex, queues, labels and wrapped logs applied')
PY
