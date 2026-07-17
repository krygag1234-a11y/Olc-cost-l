#!/usr/bin/env bash
# Olc-cost-l backend fix v2: логи tor/olcrtc показывали healthcheck.log вместо
# своих. Причина: featuresLogsHandler берёт файлы ПЕРВЫМИ, а olcrtc-healthcheck.log
# стоит в списках tor/split и (в golden) olcrtc → заслоняет journald-логи юнита.
# Фикс: для аддонов с systemd-юнитом (tor→tor@default, olcrtc→olcrtc-manager,
# webtunnel→bridge-pool) сначала пробуем ЖУРНАЛ, потом файлы.
# Idempotent. Target: manager main.go. Run after feature-logs-fix.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-feature-logs-fix-v2] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib, re
f = pathlib.Path(sys.argv[1])
t = f.read_text()

if 'journald-первым для аддонов с юнитом' in t:
    print("[patch-feature-logs-fix-v2] already applied")
    sys.exit(0)

# Якорь: начало обработчика (объявление usedPath/lines + файловый цикл).
anchor = '''		var usedPath string
		var lines []string
		for _, path := range featureLogPaths(name) {
			if st, err := os.Stat(path); err != nil || st.Size() == 0 {
				continue
			}
			got, err := tailFileLines(path, 200)
			if err != nil || len(got) == 0 {
				continue
			}
			usedPath = path
			lines = got
			break
		}'''
repl = '''		var usedPath string
		var lines []string
		// journald-первым для аддонов с юнитом (tor→tor@default, olcrtc→olcrtc-manager,
		// webtunnel→bridge-pool): их реальные логи в журнале, а olcrtc-healthcheck.log
		// в списке файлов иначе заслонял их (баг: и tor, и olcrtc показывали healthcheck).
		if unit := featureJournalUnit(name); unit != "" {
			if got, err := tailJournalUnit(unit, 200); err == nil && len(got) > 0 {
				usedPath = "journalctl -u " + unit
				lines = got
			}
		}
		if lines == nil {
			for _, path := range featureLogPaths(name) {
				if st, err := os.Stat(path); err != nil || st.Size() == 0 {
					continue
				}
				got, err := tailFileLines(path, 200)
				if err != nil || len(got) == 0 {
					continue
				}
				usedPath = path
				lines = got
				break
			}
		}'''

if anchor in t:
    t = t.replace(anchor, repl, 1)
    f.write_text(t)
    print("[patch-feature-logs-fix-v2] OK: journald-first for unit-backed features")
else:
    print("[patch-feature-logs-fix-v2] WARN: handler anchor not found (feature-logs-fix must run first)")
PY
