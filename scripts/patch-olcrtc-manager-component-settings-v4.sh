#!/usr/bin/env bash
# Zapret/Tor core fields for expanded settings UI.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'component-settings-v4' "$MAIN_GO" && { echo "[patch-component-settings-v4] already applied"; exit 0; }

python3 - "$MAIN_GO" "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
repo = Path(sys.argv[2])
t = p.read_text()

if '// component-settings-v4' not in t:
    t = t.replace('// component-settings-v3\n', '// component-settings-v3\n// component-settings-v4\n', 1)

zapret_snip = '''		zapretCfg := readTextFile(filepath.Join(olcRepoRoot(), "data/zapret-olcrtc.config"))
		if zapretCfg == "" {
			zapretCfg = readTextFile(filepath.Join(olcRepoRoot(), "data/zapret4rocket/config.default"))
		}
		if len(zapretCfg) > 800 {
			zapretCfg = zapretCfg[:800] + "\n…"
		}'''

old_z = '''		return map[string]any{
			"auto_sync":       fileExists("/etc/cron.d/olcrtc-zapret-sync") || fileExists("/etc/cron.d/zapret-sync"),
			"exclude_domains": readTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt"),
			"force_domains":   readTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt"),
			"community_sync": fileExists("/var/lib/olcrtc/lists"),
			"zapret_full":     fileExists("/opt/zapret/nfq/nfqws"),
			"strategy":        strategy,
			"nfqws_running":   false,
		}, nil'''

new_z = '''		zapretCfg := readTextFile(filepath.Join(olcRepoRoot(), "data/zapret-olcrtc.config"))
		if zapretCfg == "" {
			zapretCfg = readTextFile(filepath.Join(olcRepoRoot(), "data/zapret4rocket/config.default"))
		}
		if len(zapretCfg) > 1200 {
			zapretCfg = zapretCfg[:1200] + "\\n..."
		}
		return map[string]any{
			"auto_sync":       fileExists("/etc/cron.d/olcrtc-zapret-sync") || fileExists("/etc/cron.d/zapret-sync"),
			"exclude_domains": readTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt"),
			"force_domains":   readTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt"),
			"community_sync": fileExists("/var/lib/olcrtc/lists"),
			"zapret_full":     fileExists("/opt/zapret/nfq/nfqws"),
			"strategy":        strategy,
			"nfqws_running":   fileExists("/run/zapret/nfqws.pid") || fileExists("/opt/zapret/nfq/nfqws"),
			"nfqws_config":    zapretCfg,
			"hostlist_user":   "/opt/zapret/ipset/zapret-hosts-user.txt",
			"desync_mark":     "0x40000000",
		}, nil'''

# Only replace zapret case block if nfqws_config not present
zparts = t.split('case "zapret":')
if len(zparts) > 1 and '"nfqws_config"' not in zparts[1].split('case "tor":')[0]:
    if old_z in t:
        t = t.replace(old_z, new_z, 1)

old_tor = '''		return map[string]any{
			"socks_port":         torSocksPort(),
			"exit_nodes":         grepTorrcLine("ExitNodes"),
			"exclude_exit_nodes": grepTorrcLine("ExcludeExitNodes"),
			"strict_nodes":       grepTorrcLine("StrictNodes"),
			"bridges_enabled":  fileExists("/etc/tor/bridges.conf"),
			"socks_listen":       grepTorrcLine("SocksPort"),
		}, nil'''

new_tor = '''		return map[string]any{
			"socks_port":         torSocksPort(),
			"exit_nodes":         grepTorrcLine("ExitNodes"),
			"exclude_exit_nodes": grepTorrcLine("ExcludeExitNodes"),
			"strict_nodes":       grepTorrcLine("StrictNodes"),
			"bridges_enabled":    fileExists("/etc/tor/bridges.conf"),
			"socks_listen":       grepTorrcLine("SocksPort"),
			"socks_listen_address": grepTorrcLine("SocksListenAddress"),
			"dns_port":           grepTorrcLine("DNSPort"),
			"test_socks":         grepTorrcLine("TestSocks"),
			"safe_socks":         grepTorrcLine("SafeSocks"),
			"client_transport":   readTextFile("/etc/tor/bridges.conf"),
			"webtunnel_client":   fileExists("/usr/bin/webtunnel-client"),
		}, nil'''

tparts = t.split('case "tor":')
if len(tparts) > 1 and '"socks_listen_address"' not in tparts[1].split('case "split":')[0]:
    if old_tor in t:
        t = t.replace(old_tor, new_tor, 1)

# zapret put: allow editing nfqws core config
if 'body["nfqws_config"]' not in t:
    t = t.replace(
        '''	case "zapret":
		if v, ok := body["exclude_domains"].(string); ok {''',
        '''	case "zapret":
		if v, ok := body["exclude_domains"].(string); ok {''',
        1,
    )
    t = t.replace(
        '''		if v, ok := body["force_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["auto_sync"].(bool); ok {''',
        '''		if v, ok := body["force_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["nfqws_config"].(string); ok {
			cfgPath := filepath.Join(olcRepoRoot(), "data/zapret-olcrtc.config")
			if err := writeTextFile(cfgPath, strings.TrimSpace(v)+"\\n"); err != nil {
				return err
			}
		}
		if v, ok := body["auto_sync"].(bool); ok {''',
        1,
    )

# tor put: strict_nodes, socks_listen
if 'body["strict_nodes"]' not in t:
    t = t.replace(
        '''	case "tor":
		if v, ok := body["exit_nodes"].(string); ok {''',
        '''	case "tor":
		if v, ok := body["strict_nodes"].(string); ok {
			_ = patchTorrcKey("StrictNodes", strings.TrimSpace(v))
		}
		if v, ok := body["socks_listen"].(string); ok {
			_ = patchTorrcKey("SocksPort", strings.TrimSpace(v))
		}
		if v, ok := body["exit_nodes"].(string); ok {''',
        1,
    )

if 'func patchTorrcKey' not in t:
    patch_torrc = r'''
func patchTorrcKey(key, val string) error {
	path := "/etc/tor/torrc"
	lines := strings.Split(readTextFile(path), "\n")
	found := false
	prefix := key
	for i, line := range lines {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, prefix) {
			if val == "" {
				lines[i] = "# " + trim + " # cleared by panel"
			} else {
				lines[i] = prefix + " " + val
			}
			found = true
			break
		}
	}
	if !found && val != "" {
		lines = append(lines, prefix+" "+val)
	}
	return writeTextFile(path, strings.Join(lines, "\n"))
}

'''
    t = t.replace('func grepTorrcLine(key string) string {', patch_torrc + 'func grepTorrcLine(key string) string {', 1)

p.write_text(t)
print("[patch-component-settings-v4] ok")
PY
