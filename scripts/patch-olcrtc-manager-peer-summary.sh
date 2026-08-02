#!/usr/bin/env bash
# Olc-cost-l backend (Task 2 / оживление подгруппы «активны сейчас»):
# реализовать parsePeerSummaryLine — парсинг строки лога olcrtc-core вида
#   "Current peers count: N, Devices: [dev1 dev2 ...]"
# (реальный формат с VPS). Заполняет RuntimeState.PeerCount/PeerDevices через
# существующий logBuffer.PeerSummary() (берёт ПОСЛЕДНЮЮ такую строку в буфере).
# Устойчив к разделителю устройств (пробел/запятая) и пустому списку.
# Idempotent. Target: manager main.go.
set -euo pipefail
MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-peer-summary] ERROR: $MAIN_GO not found"; exit 1; }

if grep -q 'Current peers count:' "$MAIN_GO"; then
  echo "[patch-peer-summary] already applied"
  exit 0
fi

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()

stub = '''func parsePeerSummaryLine(line string) (int, []string, bool) {
	// Парсинг логов olcrtc для извлечения peer count
	// Формат строки из olcrtc логов (примерный): "peers: 3 [device1, device2, device3]"
	// Upstream реализация парсит специфичный формат olcrtc
	// Для совместимости оставляем заглушку, которая возвращает false
	// TODO: реализовать парсинг согласно формату логов olcrtc
	return 0, nil, false
}'''

impl = '''func parsePeerSummaryLine(line string) (int, []string, bool) {
	// Формат olcrtc-core: "Current peers count: N, Devices: [dev1 dev2 ...]"
	const marker = "Current peers count:"
	idx := strings.Index(line, marker)
	if idx < 0 {
		return 0, nil, false
	}
	rest := strings.TrimSpace(line[idx+len(marker):])
	countStr, tail, ok := strings.Cut(rest, ",")
	if !ok {
		return 0, nil, false
	}
	count, err := strconv.Atoi(strings.TrimSpace(countStr))
	if err != nil || count < 0 {
		return 0, nil, false
	}
	di := strings.Index(tail, "Devices:")
	if di < 0 {
		return 0, nil, false
	}
	devPart := strings.TrimSpace(tail[di+len("Devices:"):])
	if !strings.HasPrefix(devPart, "[") {
		return 0, nil, false
	}
	k := strings.Index(devPart, "]")
	if k < 0 {
		return 0, nil, false
	}
	devPart = devPart[1:k]
	devPart = strings.TrimSpace(devPart)
	var devices []string
	if devPart != "" {
		for _, d := range strings.FieldsFunc(devPart, func(r rune) bool { return r == ' ' || r == ',' }) {
			if d = strings.TrimSpace(d); d != "" {
				devices = append(devices, d)
			}
		}
	}
	return count, devices, true
}'''

if stub not in t:
    print("[patch-peer-summary] ERROR: parsePeerSummaryLine stub not found"); sys.exit(1)
t = t.replace(stub, impl, 1)

# --- RuntimeState: поле PeerAt (время peer-сводки, для выбора текущего инстанса) ---
rs_old = '''	PeerCount   *int     `json:"peer_count,omitempty"`
	PeerDevices []string `json:"peer_devices,omitempty"`
}'''
rs_new = '''	PeerCount   *int     `json:"peer_count,omitempty"`
	PeerDevices []string `json:"peer_devices,omitempty"`
	PeerAt      string   `json:"peer_at,omitempty"`
}'''
if 'PeerAt' not in t:
    if rs_old not in t:
        print("[patch-peer-summary] ERROR: RuntimeState anchor not found"); sys.exit(1)
    t = t.replace(rs_old, rs_new, 1)

# --- PeerSummary: возвращать также время строки ---
ps_old = '''func (b *logBuffer) PeerSummary() (int, []string, bool) {
	lines := b.Snapshot()
	for i := len(lines) - 1; i >= 0; i-- {
		if count, devices, ok := parsePeerSummaryLine(lines[i].Line); ok {
			return count, devices, true
		}
	}
	return 0, nil, false
}'''
ps_new = '''func (b *logBuffer) PeerSummary() (int, []string, string, bool) {
	lines := b.Snapshot()
	for i := len(lines) - 1; i >= 0; i-- {
		if count, devices, ok := parsePeerSummaryLine(lines[i].Line); ok {
			return count, devices, lines[i].Time, true
		}
	}
	return 0, nil, "", false
}'''
if ps_old not in t:
    print("[patch-peer-summary] ERROR: PeerSummary anchor not found"); sys.exit(1)
t = t.replace(ps_old, ps_new, 1)

peer_current = '''
func peerSummaryIsCurrent(running bool, started time.Time, at string) bool {
	if !running {
		return false
	}
	when, err := time.Parse(time.RFC3339, at)
	if err != nil {
		return false
	}
	return started.IsZero() || !when.Before(started.UTC().Truncate(time.Second))
}

func (p *process) currentPeerSummary() (int, []string, string, bool) {
	if p == nil || p.logs == nil {
		return 0, nil, "", false
	}
	p.mu.RLock()
	running, started := p.running, p.started
	p.mu.RUnlock()
	count, devices, at, ok := p.logs.PeerSummary()
	if !ok || !peerSummaryIsCurrent(running, started, at) {
		return 0, nil, "", false
	}
	return count, devices, at, true
}
'''
t = t.replace(ps_new, ps_new + peer_current, 1)

# --- state(): сохранить PeerAt ---
st_old = '''	if count, devices, ok := p.logs.PeerSummary(); ok {
		state.PeerCount = &count
		state.PeerDevices = devices
	}'''
st_new = '''	if count, devices, at, ok := p.logs.PeerSummary(); ok && peerSummaryIsCurrent(p.running, p.started, at) {
		state.PeerCount = &count
		state.PeerDevices = devices
		state.PeerAt = at
	}'''
if st_old not in t:
    print("[patch-peer-summary] ERROR: state() PeerSummary caller not found"); sys.exit(1)
t = t.replace(st_old, st_new, 1)

f.write_text(t)
test_path = f.with_name("peer_summary_patch_test.go")
test_path.write_text('package main\n\nimport "testing"\n\nfunc TestPatchedPeerSummaryParser(t *testing.T) {\n\ttests := []struct {\n\t\tname string\n\t\tline string\n\t\tcount int\n\t\tdevices int\n\t\tok bool\n\t}{\n\t\t{"spaces", "Current peers count: 2, Devices: [phone laptop]", 2, 2, true},\n\t\t{"commas", "prefix Current peers count: 2, Devices: [phone, laptop]", 2, 2, true},\n\t\t{"empty", "Current peers count: 0, Devices: []", 0, 0, true},\n\t\t{"invalid count", "Current peers count: nope, Devices: []", 0, 0, false},\n\t\t{"missing bracket", "Current peers count: 1, Devices: [phone", 0, 0, false},\n\t}\n\tfor _, tt := range tests {\n\t\tt.Run(tt.name, func(t *testing.T) {\n\t\t\tcount, devices, ok := parsePeerSummaryLine(tt.line)\n\t\t\tif ok != tt.ok || count != tt.count || len(devices) != tt.devices {\n\t\t\t\tt.Fatalf("got count=%d devices=%v ok=%v", count, devices, ok)\n\t\t\t}\n\t\t})\n\t}\n}\n')
fresh_test_path = f.with_name("peer_freshness_patch_test.go")
fresh_test_path.write_text('package main\n\nimport (\n\t"testing"\n\t"time"\n)\n\nfunc TestPeerSummaryFreshness(t *testing.T) {\n\tstart := time.Date(2026, 8, 2, 20, 0, 0, 0, time.UTC)\n\tif peerSummaryIsCurrent(false, start, "2026-08-02T20:00:01Z") { t.Fatal("stopped process must not expose peers") }\n\tif peerSummaryIsCurrent(true, start, "2026-08-02T19:59:59Z") { t.Fatal("summary from previous run must be stale") }\n\tif !peerSummaryIsCurrent(true, start, "2026-08-02T20:00:01Z") { t.Fatal("fresh running summary rejected") }\n}\n')
print("[patch-peer-summary] ok: strict parser + current-run PeerAt implemented")
PY
