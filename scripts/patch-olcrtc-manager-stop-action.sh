#!/usr/bin/env bash
# Add API action to stop a running location without deleting it.
set -euo pipefail

MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-stop-action] skip: $MAIN_GO not found"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if '"/api/actions/stop"' in t and "func (s *Supervisor) Stop(" in t:
    print("[patch-stop-action] already applied")
    raise SystemExit(0)

restart_handler = """\thandler.Handle("/api/actions/restart", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodPost {
\t\t\tw.Header().Set("Allow", http.MethodPost)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tvar req locationActionRequest
\t\tif err := json.NewDecoder(r.Body).Decode(&req); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tif err := supervisor.Restart(r.Context(), req.ClientID, req.RoomID, req.Transport); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tw.WriteHeader(http.StatusNoContent)
\t})))"""

stop_handler = """\thandler.Handle("/api/actions/stop", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodPost {
\t\t\tw.Header().Set("Allow", http.MethodPost)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tvar req locationActionRequest
\t\tif err := json.NewDecoder(r.Body).Decode(&req); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tif err := supervisor.Stop(r.Context(), req.ClientID, req.RoomID, req.Transport); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tw.WriteHeader(http.StatusNoContent)
\t})))"""

if restart_handler not in t:
    raise SystemExit("[patch-stop-action] restart handler block not found")
t = t.replace(restart_handler, restart_handler + "\n" + stop_handler, 1)

restart_method = """func (s *Supervisor) Restart(ctx context.Context, clientID, roomID, transport string) error {
\tkey := strings.Join([]string{strings.TrimSpace(clientID), strings.TrimSpace(roomID), strings.TrimSpace(transport)}, ":")

\ts.mu.Lock()
\tp, ok := s.processes[key]
\tif !ok {
\t\tloc, found := s.locationLocked(key)
\t\tif !found {
\t\t\ts.mu.Unlock()
\t\t\treturn fmt.Errorf("location %q not found", key)
\t\t}
\t\tquota := s.clientQuotaLocked(loc.ClientID)
\t\tif quotaStatus(quota, time.Now()) != "active" {
\t\t\ts.mu.Unlock()
\t\t\treturn fmt.Errorf("location %q is blocked by quota status %s", key, quotaStatus(quota, time.Now()))
\t\t}
\t\tnext, err := s.start(context.Background(), s.olcrtcPath, loc)
\t\tif err != nil {
\t\t\ts.mu.Unlock()
\t\t\treturn err
\t\t}
\t\ts.registerQuotaLocked(loc, quota, next)
\t\ts.processes[key] = next
\t\ts.monitorProcess(ctx, key, next)
\t\ts.mu.Unlock()
\t\treturn nil
\t}
\tloc := p.location
\ts.stopLocked(key)
\ts.mu.Unlock()

\tif err := waitProcessStopped(ctx, p, 5*time.Second); err != nil {
\t\treturn err
\t}

\ts.mu.Lock()
\tdefer s.mu.Unlock()
\tnext, err := s.start(context.Background(), s.olcrtcPath, loc)
\tif err != nil {
\t\treturn err
\t}
\ts.registerQuotaLocked(loc, s.clientQuotaLocked(loc.ClientID), next)
\ts.processes[key] = next
\ts.monitorProcess(ctx, key, next)
\treturn nil
}"""

stop_method = """func (s *Supervisor) Stop(ctx context.Context, clientID, roomID, transport string) error {
\tkey := strings.Join([]string{strings.TrimSpace(clientID), strings.TrimSpace(roomID), strings.TrimSpace(transport)}, ":")

\ts.mu.Lock()
\tp, ok := s.processes[key]
\tif !ok {
\t\ts.mu.Unlock()
\t\treturn nil
\t}
\ts.stopLocked(key)
\ts.mu.Unlock()
\treturn waitProcessStopped(ctx, p, 5*time.Second)
}"""

if restart_method not in t:
    raise SystemExit("[patch-stop-action] Restart() block not found")
t = t.replace(restart_method, restart_method + "\n\n" + stop_method, 1)

p.write_text(t)
print("[patch-stop-action] applied")
PY
