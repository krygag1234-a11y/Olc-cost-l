#!/usr/bin/env bash
# Extend component settings with auto_sync, tor exclude nodes, split panel hosts.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'component-settings-v2' "$MAIN_GO" && { echo "[patch-component-settings-v2] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# component-settings-v2
t = t.replace(
    '''	case "zapret":
		if v, ok := body["exclude_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["force_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt", v); err != nil {
				return err
			}
		}
		return nil''',
    '''	case "zapret":
		if v, ok := body["exclude_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["force_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["auto_sync"].(bool); ok {
			const cronPath = "/etc/cron.d/olcrtc-zapret-sync"
			if v {
				cron := "10 4 * * 0 root /opt/Olc-cost-l/scripts/zapret-sync-excludes.sh --reload-zapret >>/var/log/olcrtc-zapret-sync.log 2>&1\\n"
				if err := writeTextFile(cronPath, cron); err != nil {
					return err
				}
			} else {
				_ = os.Remove(cronPath)
			}
		}
		return nil''',
    1,
)

t = t.replace(
    '''	case "tor":
		// Tor port / exit nodes — warn only in UI; full torrc edit needs olc-update
		return nil''',
    '''	case "tor":
		if v, ok := body["exit_nodes"].(string); ok {
			if err := writeTextFile("/etc/olcrtc-manager/tor-exit.env", "OLCRTC_TOR_EXIT_NODES="+strings.TrimSpace(v)+"\\n"); err != nil {
				return err
			}
		}
		if v, ok := body["exclude_exit_nodes"].(string); ok {
			if err := writeTextFile("/etc/olcrtc-manager/tor-exit-exclude.env", "OLCRTC_TOR_EXCLUDE_EXIT="+strings.TrimSpace(v)+"\\n"); err != nil {
				return err
			}
		}
		return nil''',
    1,
)

t = t.replace(
    '''	case "split":
		if v, ok := body["custom_direct_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt", v); err != nil {
				return err
			}
		}
		return nil''',
    '''	case "split":
		if v, ok := body["custom_direct_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["panel_hosts"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/lists/panel-carrier-hosts.txt", v); err != nil {
				return err
			}
		}
		return nil''',
    1,
)

p.write_text(t)
print("[patch-component-settings-v2] ok")
PY
