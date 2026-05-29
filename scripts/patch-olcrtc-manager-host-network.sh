#!/usr/bin/env bash
# Respect OLCRTC_HOST_NETWORK=1 — run olcrtc on host (Tor SOCKS 127.0.0.1:9050 reachable).
set -euo pipefail
MAIN="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "hostNetwork :=" in t or "hostNetwork:=" in t:
    print("[patch-manager-host-network] already patched"); raise SystemExit(0)
    raise SystemExit(0)

old = """\tns, err := setupNetns(ctx, loc)
\tif err != nil {
\t\t_ = os.Remove(configPath)
\t\treturn nil, fmt.Errorf("setup netns for %s: %w", locationKey(loc), err)
\t}

\tcmdArgs := []string{"netns", "exec", ns.Name, olcrtcPath, configPath}
\tcmd := exec.CommandContext(ctx, "ip", cmdArgs...)
\tlogs := newLogBuffer(500)
\tcmd.Stdout = logWriter{stream: "stdout", buffer: logs}
\tcmd.Stderr = logWriter{stream: "stderr", buffer: logs}

\tif err := cmd.Start(); err != nil {
\t\tcleanupNetns(context.Background(), ns)
\t\t_ = os.Remove(configPath)
\t\treturn nil, fmt.Errorf("start olcrtc for %s: %w", locationKey(loc), err)
\t}

\tp := &process{location: loc, cmd: cmd, netns: ns, logs: logs, done: make(chan error, 1), started: time.Now(), running: true}
\tlog.Printf("started olcrtc for %s in %s: %s %s", locationKey(loc), ns.Name, olcrtcPath, configPath)

\tgo func() {
\t\terr := cmd.Wait()
\t\tp.markExited(err)
\t\tcleanupNetns(context.Background(), ns)
\t\t_ = os.Remove(configPath)
\t\tp.done <- err
\t}()"""

new = """\thostNetwork := strings.EqualFold(strings.TrimSpace(os.Getenv("OLCRTC_HOST_NETWORK")), "1") ||
\t\tstrings.EqualFold(strings.TrimSpace(os.Getenv("OLCRTC_HOST_NETWORK")), "true")

\tvar (
\t\tcmd *exec.Cmd
\t\tns  *netnsRuntime
\t)
\tif hostNetwork {
\t\tcmd = exec.CommandContext(ctx, olcrtcPath, configPath)
\t} else {
\t\tns, err = setupNetns(ctx, loc)
\t\tif err != nil {
\t\t\t_ = os.Remove(configPath)
\t\t\treturn nil, fmt.Errorf("setup netns for %s: %w", locationKey(loc), err)
\t\t}
\t\tcmdArgs := []string{"netns", "exec", ns.Name, olcrtcPath, configPath}
\t\tcmd = exec.CommandContext(ctx, "ip", cmdArgs...)
\t}
\tlogs := newLogBuffer(500)
\tcmd.Stdout = logWriter{stream: "stdout", buffer: logs}
\tcmd.Stderr = logWriter{stream: "stderr", buffer: logs}

\tif err := cmd.Start(); err != nil {
\t\tif ns != nil {
\t\t\tcleanupNetns(context.Background(), ns)
\t\t}
\t\t_ = os.Remove(configPath)
\t\treturn nil, fmt.Errorf("start olcrtc for %s: %w", locationKey(loc), err)
\t}

\tstartedIn := "netns"
\tif hostNetwork {
\t\tstartedIn = "host"
\t} else if ns != nil {
\t\tstartedIn = ns.Name
\t}
\tp := &process{location: loc, cmd: cmd, netns: ns, logs: logs, done: make(chan error, 1), started: time.Now(), running: true}
\tlog.Printf("started olcrtc for %s in %s: %s %s", locationKey(loc), startedIn, olcrtcPath, configPath)

\tgo func() {
\t\terr := cmd.Wait()
\t\tp.markExited(err)
\t\tif ns != nil {
\t\t\tcleanupNetns(context.Background(), ns)
\t\t}
\t\t_ = os.Remove(configPath)
\t\tp.done <- err
\t}()"""

if old not in t:
    print("patch-manager-host-network: startInstance block not found"); raise SystemExit(0)
t = t.replace(old, new, 1)
p.write_text(t)
print("[patch-manager-host-network] ok"); raise SystemExit(0)
PY
