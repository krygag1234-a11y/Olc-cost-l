#!/usr/bin/env bash
# Debounce carrier-driven smux reinstall (Telemost ICE flaps tear tunnel too aggressively).
set -euo pipefail
SERVER_GO="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/server/server.go}"
[[ -f "$SERVER_GO" ]] || exit 1

python3 - "$SERVER_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "carrierReconnectTimer" in t:
    print("[patch-server-reconnect-debounce] already patched"); raise SystemExit(0)
    raise SystemExit(0)

if "reinstallMu    sync.Mutex" not in t:
    print("Server struct anchor missing"); raise SystemExit(0)

t = t.replace(
    "\treinstallMu    sync.Mutex\n",
    "\treinstallMu           sync.Mutex\n\tcarrierReconnectMu    sync.Mutex\n\tcarrierReconnectTimer *time.Timer\n",
    1,
)

old = """func (s *Server) handleReconnect() {
\ts.recordReconnect()
\tlogger.Infof("server reconnect reason=carrier - tearing down smux session")
\ts.sessMu.RLock()
\tcurrent := s.session
\ts.sessMu.RUnlock()
\ts.reinstallSession(current)
}"""

new = """func (s *Server) handleReconnect() {
\tconst debounce = 5 * time.Second
\ts.carrierReconnectMu.Lock()
\tif s.carrierReconnectTimer != nil {
\t\ts.carrierReconnectTimer.Stop()
\t}
\ts.carrierReconnectTimer = time.AfterFunc(debounce, func() {
\t\ts.carrierReconnectMu.Lock()
\t\ts.carrierReconnectTimer = nil
\t\ts.carrierReconnectMu.Unlock()
\t\ts.recordReconnect()
\t\tlogger.Infof("server reconnect reason=carrier - tearing down smux session (debounced %v)", debounce)
\t\ts.sessMu.RLock()
\t\tcurrent := s.session
\t\ts.sessMu.RUnlock()
\t\ts.reinstallSession(current)
\t})
\ts.carrierReconnectMu.Unlock()
}"""

if old not in t:
    print("handleReconnect block not found"); raise SystemExit(0)
t = t.replace(old, new, 1)
p.write_text(t)
print("[patch-server-reconnect-debounce] ok (5s debounce)"); raise SystemExit(0)
PY
