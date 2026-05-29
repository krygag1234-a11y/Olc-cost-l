#!/usr/bin/env bash
# olcrtc settings v2: carrier/transport/socks/warp/proxies in panel.env.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'OLCRTC_DEFAULT_CARRIER' "$MAIN_GO" && { echo "[patch-olcrtc-settings-v2] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

for key in [
    "OLCRTC_WARP_PROXY",
    "OLCRTC_SOCKS_PROXY",
    "OLCRTC_DEFAULT_CARRIER",
    "OLCRTC_DEFAULT_TRANSPORT",
    "OLCRTC_DEFAULT_LINK",
    "OLCRTC_TOR_PROXY",
    "OLCRTC_WEBRTC_PROXY",
]:
    if key not in t:
        t = t.replace(
            '"OLCRTC_FORCE_TOR_DOMAINS":  true,',
            f'"OLCRTC_FORCE_TOR_DOMAINS":  true,\n\t\t"{key}":  true,',
            1,
        )

if '"warp_proxy":' not in t:
    t = t.replace(
        '''		"force_tor_file":      env["OLCRTC_FORCE_TOR_DOMAINS"],
		"olcrtc_branch":        "master",''',
        '''		"force_tor_file":      env["OLCRTC_FORCE_TOR_DOMAINS"],
		"warp_proxy":          env["OLCRTC_WARP_PROXY"],
		"socks_proxy":         env["OLCRTC_SOCKS_PROXY"],
		"default_carrier":     env["OLCRTC_DEFAULT_CARRIER"],
		"default_transport":   env["OLCRTC_DEFAULT_TRANSPORT"],
		"default_link":        env["OLCRTC_DEFAULT_LINK"],
		"tor_proxy":           env["OLCRTC_TOR_PROXY"],
		"webrtc_proxy":        env["OLCRTC_WEBRTC_PROXY"],
		"olcrtc_branch":        "master",''',
        1,
    )

if 'body["warp_proxy"]' not in t:
    t = t.replace(
        '''	if v, ok := body["public_url"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_PUBLIC_URL", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	return nil''',
        '''	if v, ok := body["public_url"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_PUBLIC_URL", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["warp_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_WARP_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["socks_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_SOCKS_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["default_carrier"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_DEFAULT_CARRIER", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["default_transport"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_DEFAULT_TRANSPORT", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["default_link"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_DEFAULT_LINK", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["tor_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_TOR_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	if v, ok := body["webrtc_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_WEBRTC_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	return nil''',
        1,
    )

p.write_text(t)
print("[patch-olcrtc-settings-v2] ok")
PY
