#!/usr/bin/env bash
# Jitsi rebuilds colibri/bridge internally — do not tear down client smux on carrier reconnect.
set -euo pipefail
SERVER_GO="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1

python3 - "$SERVER_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "linkCarrier string" in t:
    print("[patch-jitsi-no-smux] carrier field already present")
else:
    if "carrierReconnectTimer *time.Timer" not in t:
        raise SystemExit("run patch-olcrtc-server-reconnect-debounce.sh first")
    t = t.replace(
        "\tcarrierReconnectTimer *time.Timer\n",
        "\tcarrierReconnectTimer *time.Timer\n\tlinkCarrier            string\n\tlinkTransport          string\n",
        1,
    )
    if "s.linkCarrier = cfg.Carrier" not in t:
        t = t.replace(
            "\ts.ln = ln\n",
            "\ts.ln = ln\n\ts.linkCarrier = cfg.Carrier\n\ts.linkTransport = cfg.Transport\n",
            1,
        )

marker = "server reconnect reason=carrier - tearing down smux session"
if marker not in t:
    raise SystemExit("handleReconnect debounce block not found")

skip = """\t\tif strings.EqualFold(s.linkCarrier, "jitsi") {
\t\t\tlogger.Infof("server reconnect reason=carrier - skip smux reinstall (jitsi bridge reconnect is internal)")
\t\t\treturn
\t\t}
"""
if "skip smux reinstall (jitsi" not in t:
    t = t.replace(
        "\t\ts.recordReconnect()\n\t\tlogger.Infof(\"server reconnect reason=carrier - tearing down smux session (debounced %v)\", debounce)",
        "\t\ts.recordReconnect()\n" + skip + "\t\tlogger.Infof(\"server reconnect reason=carrier - tearing down smux session (debounced %v)\", debounce)",
        1,
    )

if '"strings"' not in t and "strings.EqualFold" in t:
    t = t.replace('"strconv"\n\t"sync"', '"strconv"\n\t"strings"\n\t"sync"', 1)

p.write_text(t)
print("[patch-jitsi-no-smux] ok")
PY
