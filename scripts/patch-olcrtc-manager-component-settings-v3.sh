#!/usr/bin/env bash
# Extended zapret/tor/split settings fields.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'component-settings-v3' "$MAIN_GO" && { echo "[patch-component-settings-v3] already applied"; exit 0; }

python3 - "$MAIN_GO" "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
repo = Path(sys.argv[2])
t = p.read_text()

marker = '// component-settings-v3\n'

get_zapret = '''	case "zapret":
		return map[string]any{
			"auto_sync":            fileExists("/etc/cron.d/olcrtc-zapret-sync") || fileExists("/etc/cron.d/zapret-sync"),
			"exclude_domains":      readTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt"),
			"force_domains":        readTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt"),
			"community_sync":       fileExists("/var/lib/olcrtc/lists"),
		}, nil'''

get_zapret_new = '''	case "zapret":
		strategy := ""
		if b := readTextFile(filepath.Join(olcRepoRoot(), "data/zapret4rocket/config.default")); b != "" {
			strategy = "z4r-config.default"
		}
		return map[string]any{
			"auto_sync":       fileExists("/etc/cron.d/olcrtc-zapret-sync") || fileExists("/etc/cron.d/zapret-sync"),
			"exclude_domains": readTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt"),
			"force_domains":   readTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt"),
			"community_sync": fileExists("/var/lib/olcrtc/lists"),
			"zapret_full":     fileExists("/opt/zapret/nfq/nfqws"),
			"strategy":        strategy,
			"nfqws_running":   false,
		}, nil'''

if get_zapret in t:
    t = t.replace(get_zapret, get_zapret_new, 1)

get_tor = '''	case "tor":
		return map[string]any{
			"socks_port":           torSocksPort(),
			"exit_nodes":           grepTorrcLine("ExitNodes"),
			"exclude_exit_nodes":   grepTorrcLine("ExcludeExitNodes"),
			"bridges_enabled":      fileExists("/etc/tor/bridges.conf"),
		}, nil'''

get_tor_new = '''	case "tor":
		return map[string]any{
			"socks_port":         torSocksPort(),
			"exit_nodes":         grepTorrcLine("ExitNodes"),
			"exclude_exit_nodes": grepTorrcLine("ExcludeExitNodes"),
			"strict_nodes":       grepTorrcLine("StrictNodes"),
			"bridges_enabled":  fileExists("/etc/tor/bridges.conf"),
			"socks_listen":       grepTorrcLine("SocksPort"),
		}, nil'''

if get_tor in t:
    t = t.replace(get_tor, get_tor_new, 1)

get_split = '''	case "split":
		return map[string]any{
			"custom_direct_domains": readTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt"),
			"panel_hosts":           readTextFile("/var/lib/olcrtc/lists/panel-carrier-hosts.txt"),
			"ru_direct_count":       countLines("/var/lib/olcrtc/ru-direct-domains.txt"),
		}, nil'''

get_split_new = '''	case "split":
		env := readPanelEnvMap()
		return map[string]any{
			"custom_direct_domains": readTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt"),
			"panel_hosts":           readTextFile("/var/lib/olcrtc/lists/panel-carrier-hosts.txt"),
			"force_tor_domains":     readTextFile("/var/lib/olcrtc/force-tor-domains.txt"),
			"blocked_tor_domains":   readTextFile("/var/lib/olcrtc/ru-blocked-tor-domains.txt"),
			"ru_direct_count":       countLines("/var/lib/olcrtc/ru-direct-domains.txt"),
			"direct_cidrs_file":     env["OLCRTC_DIRECT_CIDRS"],
			"cidr_only":             strings.Contains(env["OLCRTC_DIRECT_CIDRS"], "ru-cidrs"),
		}, nil'''

if get_split in t:
    t = t.replace(get_split, get_split_new, 1)

# zapret put: zapret_full flag
if 'body["zapret_full"]' not in t:
    t = t.replace(
        '''		if v, ok := body["auto_sync"].(bool); ok {''',
        '''		if v, ok := body["force_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/force-tor-domains.txt", v)
		}
		if v, ok := body["blocked_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/ru-blocked-tor-domains.txt", v)
		}
		if v, ok := body["auto_sync"].(bool); ok {''',
        1,
    )
    # wrong placement - only in split case
    t = t.replace(
        '''		if v, ok := body["force_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/force-tor-domains.txt", v)
		}
		if v, ok := body["blocked_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/ru-blocked-tor-domains.txt", v)
		}
		if v, ok := body["auto_sync"].(bool); ok {''',
        '''		if v, ok := body["auto_sync"].(bool); ok {''',
        1,
    )

if 'case "split":' in t and 'force_tor_domains' not in t.split('case "split":')[1].split('case "bridges"')[0]:
    t = t.replace(
        '''	case "split":
		if v, ok := body["custom_direct_domains"].(string); ok {''',
        '''	case "split":
		if v, ok := body["force_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/force-tor-domains.txt", v)
		}
		if v, ok := body["blocked_tor_domains"].(string); ok {
			_ = writeTextFile("/var/lib/olcrtc/ru-blocked-tor-domains.txt", v)
		}
		if v, ok := body["custom_direct_domains"].(string); ok {''',
        1,
    )

if marker not in t:
    t = t.replace('func componentSettingsHandler()', marker + 'func componentSettingsHandler()', 1)

p.write_text(t)
print("[patch-component-settings-v3] ok")
PY
