#!/usr/bin/env bash
# Hotfix v12: feature logs — skip empty files, olcrtc paths order, journalctl fallback.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

new_flp = r'''func featureLogPaths(name string) []string {
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
		}
	case "webtunnel":
		return []string{
			"/var/log/olcrtc-bridge-pool.log",
			"/var/log/olcrtc-bridge-monitor.log",
			"/var/log/olcrtc-component-bridges-install.log",
			"/var/log/olcrtc-component-bridges-uninstall.log",
		}
	case "warp":
		return []string{
			"/var/log/olcrtc-warp-install.log",
			"/var/log/olcrtc-component-warp-install.log",
			"/var/log/olcrtc-component-warp-uninstall.log",
		}
	case "olcrtc":
		return []string{
			"/var/log/olcrtc-healthcheck.log",
			"/var/log/olcrtc-panel-update.log",
			"/var/log/olcrtc-feature-restart.log",
		}
	default:
		return nil
	}
}'''

pat = r"func featureLogPaths\(name string\) \[\]string \{[\s\S]*?\n\}\n\nfunc tailFileLines"
m = re.search(pat, t)
if m:
    t = t[: m.start()] + new_flp + "\n\nfunc tailFileLines" + t[m.end() :]
elif "case \"olcrtc\":" not in t:
    t2, n = re.subn(
        r"func featureLogPaths\(name string\) \[\]string \{[\s\S]*?\n\}",
        new_flp,
        t,
        count=1,
    )
    if n:
        t = t2

if "func tailJournalUnit" not in t:
    journal_fn = r'''
func tailJournalUnit(unit string, maxLines int) ([]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "journalctl", "-u", unit, "-n", fmt.Sprintf("%d", maxLines), "--no-pager", "-o", "cat")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, err
	}
	text := strings.TrimSpace(string(out))
	if text == "" {
		return nil, fmt.Errorf("empty journal")
	}
	lines := strings.Split(text, "\n")
	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
	}
	return lines, nil
}

'''
    t = t.replace("func tailFileLines(path string, maxLines int)", journal_fn + "func tailFileLines(path string, maxLines int)", 1)

old_loop = '''		var usedPath string
		var lines []string
		for _, path := range featureLogPaths(name) {
			got, err := tailFileLines(path, 200)
			if err != nil {
				continue
			}
			usedPath = path
			lines = got
			break
		}
		if lines == nil {
			paths := featureLogPaths(name)
			msg := fmt.Sprintf("(log file not found for %s — tried: %s)", name, strings.Join(paths, ", "))
			if len(paths) == 0 {
				msg = fmt.Sprintf("(no log paths configured for %s)", name)
			}
			lines = []string{msg}
		}
		writeJSON(w, map[string]any{"feature": name, "path": usedPath, "lines": lines})'''

new_loop = '''		var usedPath string
		var lines []string
		for _, path := range featureLogPaths(name) {
			got, err := tailFileLines(path, 200)
			if err != nil || len(got) == 0 {
				continue
			}
			usedPath = path
			lines = got
			break
		}
		if lines == nil && name == "olcrtc" {
			if got, err := tailJournalUnit("olcrtc-manager.service", 200); err == nil && len(got) > 0 {
				usedPath = "journalctl:olcrtc-manager.service"
				lines = got
			}
		}
		if lines == nil && name == "warp" {
			if got, err := tailJournalUnit("warp-svc.service", 120); err == nil && len(got) > 0 {
				usedPath = "journalctl:warp-svc.service"
				lines = got
			}
		}
		if lines == nil {
			paths := featureLogPaths(name)
			msg := fmt.Sprintf("(log file not found for %s — tried: %s)", name, strings.Join(paths, ", "))
			if len(paths) == 0 {
				msg = fmt.Sprintf("(no log paths configured for %s)", name)
			}
			lines = []string{msg}
		}
		writeJSON(w, map[string]any{"feature": name, "path": usedPath, "lines": lines})'''

if old_loop in t:
    t = t.replace(old_loop, new_loop, 1)

# Refresh webtunnel_client in bridge pool status from disk on read.
if "func readBridgePoolStatus()" in t and "webtunnel_client" not in t.split("func readBridgePoolStatus()")[1].split("func writeBridgePoolStatus")[0]:
    t = t.replace(
        "func readBridgePoolStatus() map[string]any {\n\tvar st map[string]any\n\tif readJSONFile(bridgePoolStatusFile, &st) {\n\t\treturn st\n\t}\n\treturn map[string]any{\"status\": \"idle\"}\n}",
        "func readBridgePoolStatus() map[string]any {\n\tvar st map[string]any\n\tif readJSONFile(bridgePoolStatusFile, &st) {\n\t\tst[\"webtunnel_client\"] = fileExists(\"/usr/bin/webtunnel-client\") || fileExists(\"/usr/local/bin/webtunnel-client\")\n\t\treturn st\n\t}\n\treturn map[string]any{\"status\": \"idle\", \"webtunnel_client\": fileExists(\"/usr/bin/webtunnel-client\")}\n}",
        1,
    )

if "olc-manager-hotfix-v12" not in t:
    if "/* olc-manager-hotfix-v11 */" in t:
        t = t.replace("/* olc-manager-hotfix-v11 */", "/* olc-manager-hotfix-v11 */\n/* olc-manager-hotfix-v12 */", 1)
    else:
        t = "/* olc-manager-hotfix-v12 */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v12] ok")
PY
