#!/usr/bin/env bash
# Idempotent fixes: bridge consts, olcrtc logs, corrupted componentInstalled/componentSettingsPut.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-go-fixes-v3' "$MAIN_GO" && { echo "[patch-go-fixes] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Remove accidental olcrtcSettingsPut injection inside componentInstalled
bad = '''func componentInstalled(name string) bool {
	if name == "olcrtc" {
		if err := olcrtcSettingsPut(body); err != nil {
			return err
		}
		return nil
	}
	switch name {'''
good = '''func componentInstalled(name string) bool {
	switch name {'''
if bad in t:
    t = t.replace(bad, good, 1)

# Fix componentSettingsPut: olcrtc before switch, not inside
bad2 = '''func componentSettingsPut(name string, body map[string]any) error {
	switch name {
	if name == "olcrtc" {
		return olcrtcSettingsPut(body)
	}
	case "zapret":'''
good2 = '''func componentSettingsPut(name string, body map[string]any) error {
	if name == "olcrtc" {
		return olcrtcSettingsPut(body)
	}
	switch name {
	case "zapret":'''
if bad2 in t:
    t = t.replace(bad2, good2, 1)

# Bridge path constants inside panelBackendV4 const block
const_old = '''const (
	panelUpdateLock  = "/var/lib/olcrtc/panel-update.lock"
	panelUpdateStatus = "/var/lib/olcrtc/panel-update-status.json"
	panelJobsDir     = "/var/lib/olcrtc/panel-jobs"
	panelNotifFile   = "/var/lib/olcrtc/notifications.json"
)'''
const_new = '''const (
	panelUpdateLock    = "/var/lib/olcrtc/panel-update.lock"
	panelUpdateStatus  = "/var/lib/olcrtc/panel-update-status.json"
	panelJobsDir       = "/var/lib/olcrtc/panel-jobs"
	panelNotifFile     = "/var/lib/olcrtc/notifications.json"
	bridgeProfilesPath = "/var/lib/olcrtc/bridge-profiles.json"
	bridgeCronPath     = "/etc/cron.d/olcrtc-bridge-pool"
)'''
if 'bridgeProfilesPath =' not in t and const_old in t:
    t = t.replace(const_old, const_new, 1)

# olcrtc in feature logs whitelist
fn_parts = t.split('var featureNames = ')
if len(fn_parts) > 1 and '"olcrtc"' not in fn_parts[1].split(']')[0]:
    t = t.replace(
        'var featureNames = []string{"zapret", "tor", "split", "webtunnel"}',
        'var featureNames = []string{"zapret", "tor", "split", "webtunnel", "olcrtc"}',
        1,
    )

fl_parts = t.split('func featureLogPaths')
if len(fl_parts) > 1 and 'case "olcrtc":' not in fl_parts[1].split('func tailFileLines')[0]:
    t = t.replace(
        '''	case "webtunnel":
		return []string{"/var/log/olcrtc-healthcheck.log"}
	default:''',
        '''	case "webtunnel":
		return []string{"/var/log/olcrtc-bridge-pool.log", "/var/log/olcrtc-healthcheck.log"}
	case "olcrtc":
		return []string{
			"/var/log/olcrtc-healthcheck.log",
			filepath.Join(olcRepoRoot(), "logs/olcrtc-manager.log"),
			"/var/log/syslog",
		}
	default:''',
        1,
    )

# olcrtcSettingsGet: drop unused pins if sha helper missing
if 'func olcrtcSettingsGet()' in t:
    block = t.split('func olcrtcSettingsGet()')[1].split('\nfunc ')[0]
    if 'pins := readPins' in block and 'olcrtc_pinned_sha":  sha' not in block:
        t = t.replace(
            '''	pins := readPins(olcRepoRoot())
	return map[string]any{''',
            '''	pins := readPins(olcRepoRoot())
	sha := ""
	if o, ok := pins["olcrtc"].(map[string]any); ok {
		if s, ok := o["pinned_sha"].(string); ok {
			sha = s
		}
	}
	return map[string]any{''',
            1,
        )
        t = t.replace('"olcrtc_pinned_sha":  "",', '"olcrtc_pinned_sha":  sha,', 1)
    elif 'pins := readPins' in block and 'sha :=' not in block:
        t = t.replace('\tpins := readPins(olcRepoRoot())\n', '', 1)

# notification-settings route (handler may exist without route)
route = '\thandler.Handle("/api/notification-settings", adminAuth(http.HandlerFunc(notificationSettingsHandler)))\n'
if '"/api/notification-settings"' not in t:
    for anchor in (
        '\thandler.Handle("/api/project/status", adminAuth(http.HandlerFunc(projectStatusHandler)))',
        '\thandler.Handle("/api/notifications", adminAuth(http.HandlerFunc(notificationsListHandler())))',
    ):
        if anchor in t:
            t = t.replace(anchor, route + anchor, 1)
            break

# Sanitize broken literal newlines in Go strings from older patches
t = re.sub(r'lines := strings\.Split\(readTextFile\(path\), "\s*\n\s*"\)', 'lines := strings.Split(readTextFile(path), "\\n")', t)
t = re.sub(r'strings\.Join\(lines, "\s*\n\s*"\)', 'strings.Join(lines, "\\n")', t)
t = re.sub(r'zapretCfg = zapretCfg\[:1200\] \+ "\s*\n[^"]*"', 'zapretCfg = zapretCfg[:1200] + "\\n..."', t)

if '// olc-go-fixes-v3' not in t:
    t = t.replace('// olc-go-fixes-v2', '// olc-go-fixes-v3', 1) if '// olc-go-fixes-v2' in t else (
        t.replace('// olc-go-fixes-v1', '// olc-go-fixes-v3', 1) if '// olc-go-fixes-v1' in t else t.replace('package main\n', 'package main\n\n// olc-go-fixes-v3\n', 1)
    )

p.write_text(t)
print("[patch-go-fixes] ok")
PY
