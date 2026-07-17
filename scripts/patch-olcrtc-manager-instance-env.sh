#!/usr/bin/env bash
# Olc-cost-l backend: прокинуть client_id/room_id инстанса в процесс olcrtc через
# env (OLCRTC_CLIENT_ID / OLCRTC_ROOM_ID / OLCRTC_INSTANCE). Нужно для per-client
# и per-instance решений в AuthHook olcrtc-core (patch-olcrtc-core-access-hook).
# startInstance не задаёт cmd.Env (olcrtc наследует окружение менеджера) — добавляем
# явные переменные ПЕРЕД запуском. В netns-режиме `ip netns exec` сохраняет env.
# Idempotent. Target: manager main.go.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-instance-env] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()

if 'OLCRTC_CLIENT_ID=' in t:
    print("[patch-instance-env] already present")
    sys.exit(0)

anchor = '\tlogs := newLogBuffer(500)\n\tcmd.Stdout = logWriter{stream: "stdout", buffer: logs}'
repl = ('\t// Olc-cost-l: прокидываем идентификаторы клиента/инстанса для AuthHook\n'
        '\t// olcrtc-core (per-client / per-instance контроль подключения).\n'
        '\tcmd.Env = append(os.Environ(),\n'
        '\t\t"OLCRTC_CLIENT_ID="+loc.ClientID,\n'
        '\t\t"OLCRTC_ROOM_ID="+loc.Endpoint.RoomID,\n'
        '\t\t"OLCRTC_INSTANCE="+locationKey(loc))\n'
        '\tlogs := newLogBuffer(500)\n\tcmd.Stdout = logWriter{stream: "stdout", buffer: logs}')

if anchor in t:
    t = t.replace(anchor, repl, 1)
    f.write_text(t)
    print("[patch-instance-env] OK: OLCRTC_CLIENT_ID/ROOM_ID/INSTANCE wired into startInstance")
else:
    print("[patch-instance-env] WARN: startInstance logs anchor not found — skip")
PY
