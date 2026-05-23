#!/usr/bin/env bash
# Idempotent VPS manager patches when olcrtc-manager-main.go.patch fails on upstream drift.
set -euo pipefail
MAIN="${1:-/tmp/olcrtc-manager-panel/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "exitProxyReachable" not in t:
    insert_after = "func directCIDRsFileFromEnv() string {"
    if insert_after not in t:
        # add stub before serverConfig
        insert_after = "func serverConfig(loc Location)"
    block = '''
func exitProxyReachable(addr string, port int) bool {
	if addr == "" || port <= 0 {
		return false
	}
	d := net.Dialer{Timeout: 2 * time.Second}
	conn, err := d.Dial("tcp", net.JoinHostPort(addr, strconv.Itoa(port)))
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func exitProxyFromEnv() (addr string, port int) {
	raw := strings.TrimSpace(os.Getenv("OLCRTC_EXIT_PROXY"))
	if raw == "" {
		addr = strings.TrimSpace(os.Getenv("OLCRTC_EXIT_PROXY_ADDR"))
		if addr == "" {
			return "", 0
		}
		port, _ = strconv.Atoi(strings.TrimSpace(os.Getenv("OLCRTC_EXIT_PROXY_PORT")))
		if port <= 0 {
			port = 9050
		}
	} else {
		host, portStr, err := net.SplitHostPort(raw)
		if err != nil {
			addr, port = raw, 9050
		} else {
			addr = host
			port, _ = strconv.Atoi(portStr)
			if port <= 0 {
				port = 9050
			}
		}
	}
	if addr == "" {
		return "", 0
	}
	if !exitProxyReachable(addr, port) {
		log.Printf("exit proxy %s:%d unreachable, olcrtc runs without SOCKS (Jitsi stays up)", addr, port)
		return "", 0
	}
	return addr, port
}

'''
    if insert_after == "func serverConfig(loc Location)":
        t = t.replace(insert_after, block + insert_after, 1)
    else:
        # after directCIDRsFileFromEnv closing brace — insert before serverConfig
        m = re.search(r"func directCIDRsFileFromEnv\(\) string \{[\s\S]*?\n\}\n", t)
        if m:
            t = t[: m.end()] + block + t[m.end() :]
        else:
            raise SystemExit("cannot place exitProxyFromEnv")

# serverConfig SOCKS block
if "exitProxyFromEnv()" in t and "DirectCIDRsFile: directCIDRsFileFromEnv()" not in t:
    t = t.replace(
        "if proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != \"\" {",
        "if proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != \"\" {",
    )
    t = re.sub(
        r"if proxyAddr, proxyPort := exitProxyFromEnv\(\); proxyAddr != \"\" \{\n\t\tcfg\.SOCKS = olcrtcSocksConfig\{[\s\S]*?\n\t\t\}\n\t\}",
        """if proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
		cfg.SOCKS = olcrtcSocksConfig{
			ProxyAddr:             proxyAddr,
			ProxyPort:             proxyPort,
			DirectCIDRsFile:       directCIDRsFileFromEnv(),
			DirectDomainsFile:     directDomainsFileFromEnv(),
			BlockedTorDomainsFile: blockedTorDomainsFileFromEnv(),
			ForceTorDomainsFile:   forceTorDomainsFileFromEnv(),
		}
	}""",
        t,
        count=1,
    )

# HOST_NETWORK: use olcrtc-manager-main.go.patch or upstream startInstance with hostNetwork branch

p.write_text(t)
print("[patch-manager-core] ok")
PY
