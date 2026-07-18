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
	rest := line[idx+len(marker):]
	di := strings.Index(rest, "Devices:")
	if di < 0 {
		return 0, nil, false
	}
	countStr := strings.TrimSpace(strings.TrimRight(strings.TrimSpace(rest[:di]), ","))
	count := 0
	if _, err := fmt.Sscanf(countStr, "%d", &count); err != nil {
		count = 0
	}
	devPart := strings.TrimSpace(rest[di+len("Devices:"):])
	devPart = strings.TrimPrefix(devPart, "[")
	if k := strings.Index(devPart, "]"); k >= 0 {
		devPart = devPart[:k]
	}
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
f.write_text(t)
print("[patch-peer-summary] ok: parsePeerSummaryLine implemented")
PY
