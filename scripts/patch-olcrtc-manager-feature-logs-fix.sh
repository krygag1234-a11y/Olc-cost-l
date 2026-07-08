#!/usr/bin/env bash
# Fix feature-log resolution: correct file paths + journald fallback so every
# addon (zapret/tor/split/webtunnel/olcrtc) shows its OWN real logs instead of
# "(log file not found ...)".
#   - zapret: add /var/log/olcrtc-zapret-install.log
#   - split:  add /var/log/olcrtc-split-update.log
#   - tor:    journald unit tor@default (real bootstrap/handshake logs)
#   - olcrtc: journald unit olcrtc-manager
#   - webtunnel: journald unit olcrtc-tor-bridge-pool as fallback
# Idempotent. Target: manager main.go. Run after golden-panel copy.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-feature-logs-fix] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Correct file paths in featureLogPaths ---
paths_old = '''func featureLogPaths(name string) []string {
	switch name {
	case "zapret":
		return []string{
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-component-zapret-install.log",
			"/var/log/olcrtc-component-zapret-uninstall.log",
		}
	case "tor":
		return []string{"/var/log/olcrtc-healthcheck.log", "/var/log/tor/log"}
	case "split":
		return []string{
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-healthcheck.log",
			"/var/log/olcrtc-component-split-install.log",
			"/var/log/olcrtc-component-split-uninstall.log",
		}'''
paths_new = '''func featureLogPaths(name string) []string {
	switch name {
	case "zapret":
		return []string{
			"/var/log/olcrtc-zapret-install.log",
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-component-zapret-install.log",
			"/var/log/olcrtc-component-zapret-uninstall.log",
		}
	case "tor":
		return []string{"/var/log/tor/log", "/var/log/olcrtc-healthcheck.log"}
	case "split":
		return []string{
			"/var/log/olcrtc-split-update.log",
			"/var/log/olcrtc-zapret-sync.log",
			"/var/log/olcrtc-healthcheck.log",
			"/var/log/olcrtc-component-split-install.log",
			"/var/log/olcrtc-component-split-uninstall.log",
		}'''
if '"/var/log/olcrtc-zapret-install.log",' in t and '"/var/log/olcrtc-split-update.log",' in t:
    print("[patch-feature-logs-fix] file paths already corrected")
elif paths_old in t:
    t = t.replace(paths_old, paths_new, 1)
    changed = True
    print("[patch-feature-logs-fix] corrected zapret/tor/split file paths")
else:
    print("[patch-feature-logs-fix] WARN: featureLogPaths anchor not found")

# --- 2. Add journald-unit fallback map ---
if 'func featureJournalUnit(' not in t:
    helper = '''
// featureJournalUnit maps an addon to a systemd unit whose journal carries its
// real logs, used as a fallback when no populated log file exists.
func featureJournalUnit(name string) string {
	switch name {
	case "tor":
		return "tor@default"
	case "olcrtc":
		return "olcrtc-manager"
	case "webtunnel":
		return "olcrtc-tor-bridge-pool"
	default:
		return ""
	}
}

'''
    anchor = 'func featureLogPaths(name string) []string {'
    if anchor in t:
        t = t.replace(anchor, helper + anchor, 1)
        changed = True
        print("[patch-feature-logs-fix] added featureJournalUnit map")
    else:
        print("[patch-feature-logs-fix] WARN: cannot place featureJournalUnit")
else:
    print("[patch-feature-logs-fix] featureJournalUnit already present")

# --- 3. In the handler, fall back to journald when no file matched ---
handler_old = '''		if lines == nil {
			paths := featureLogPaths(name)
			msg := fmt.Sprintf("(log file not found for %s — tried: %s)", name, strings.Join(paths, ", "))
			if len(paths) == 0 {
				msg = fmt.Sprintf("(no log paths configured for %s)", name)
			}
			lines = []string{msg}
		}'''
handler_new = '''		if lines == nil {
			if unit := featureJournalUnit(name); unit != "" {
				if got, err := tailJournalUnit(unit, 200); err == nil && len(got) > 0 {
					usedPath = "journalctl -u " + unit
					lines = got
				}
			}
		}
		if lines == nil {
			paths := featureLogPaths(name)
			tried := append([]string{}, paths...)
			if unit := featureJournalUnit(name); unit != "" {
				tried = append(tried, "journalctl -u "+unit)
			}
			msg := fmt.Sprintf("(no logs yet for %s — tried: %s)", name, strings.Join(tried, ", "))
			if len(tried) == 0 {
				msg = fmt.Sprintf("(no log sources configured for %s)", name)
			}
			lines = []string{msg}
		}'''
if 'if unit := featureJournalUnit(name); unit != ""' in t:
    print("[patch-feature-logs-fix] handler journald fallback already present")
elif handler_old in t:
    t = t.replace(handler_old, handler_new, 1)
    changed = True
    print("[patch-feature-logs-fix] handler falls back to journald")
else:
    print("[patch-feature-logs-fix] WARN: handler anchor not found")

if changed:
    f.write_text(t)
print("[patch-feature-logs-fix] ok")
PY
