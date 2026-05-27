#!/usr/bin/env bash
# Jitsi preflight v4: add post-join bridge compatibility hint fields.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-jitsi-preflight-v4' "$MAIN_GO" && { echo "[patch-jitsi-preflight-v4] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "BridgePostJoinRisk bool" not in t:
    t = t.replace(
        'BOSHCode int     `json:"bosh_status,omitempty"`\n}',
        'BOSHCode int     `json:"bosh_status,omitempty"`\n\tBridgePostJoinRisk bool   `json:"bridge_postjoin_risk,omitempty"`\n\tBridgePostJoinNote string `json:"bridge_postjoin_note,omitempty"`\n}',
        1,
    )

hook = """\tout.Host = u.Host
\tout.Room = room
"""
inject = """\tout.Host = u.Host
\tout.Room = room
\thostOnly := u.Hostname()
\tif ip := net.ParseIP(hostOnly); ip != nil {
\t\tout.BridgePostJoinRisk = true
\t\tout.BridgePostJoinNote = "IP-хост: после join обязательно проверьте bridge websocket в runtime-логе"
\t}
"""
if hook in t and "hostOnly := u.Hostname()" not in t:
    t = t.replace(hook, inject, 1)

ok_old = """\tif mainWSCode == 101 || mainWSCode == 200 || mainWSCode == 426 {
\t\tout.OK = true
\t\tout.Code = "ok"
\t\tout.Summary = "Базовая Jitsi-проверка пройдена"
\t\tout.Details = []string{fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode)}
\t\treturn out
\t}
"""
ok_new = """\tif mainWSCode == 101 || mainWSCode == 200 || mainWSCode == 426 {
\t\tout.OK = true
\t\tout.Code = "ok"
\t\tout.Summary = "Базовая Jitsi-проверка пройдена"
\t\tout.Details = []string{fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode)}
\t\tif out.BridgePostJoinRisk || mainWSCode == 200 {
\t\t\tout.BridgePostJoinRisk = true
\t\t\tif out.BridgePostJoinNote == "" {
\t\t\t\tout.BridgePostJoinNote = "Проверяйте post-join в runtime: bridge websocket должен дать HTTP 101 (а не 200)"
\t\t\t}
\t\t\tout.Details = append(out.Details, "Bridge WS compatibility: ориентир в runtime - \"bridge open\" / \"Link connected\"")
\t\t}
\t\treturn out
\t}
"""
if ok_old in t:
    t = t.replace(ok_old, ok_new, 1)

weak_old = """\tout.OK = true
\tout.Code = "weak-signal"
\tout.Summary = "Предпроверка не нашла явного блокера, но результат не окончательный"
\tout.Details = []string{
\t\tfmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode),
\t\t"Финальный статус определяется runtime-логом jitsi join",
\t}
\treturn out
}"""
weak_new = """\tout.OK = true
\tout.Code = "weak-signal"
\tout.Summary = "Предпроверка не нашла явного блокера, но результат не окончательный"
\tout.Details = []string{
\t\tfmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode),
\t\t"Финальный статус определяется runtime-логом jitsi join",
\t\t"Bridge WS compatibility (post-join): ошибка \\\"expected 101 but got 200\\\" = инстанс нерабочий",
\t}
\tif out.BridgePostJoinNote == "" {
\t\tout.BridgePostJoinRisk = true
\t\tout.BridgePostJoinNote = "Проверьте post-join runtime-лог: при проблеме будет \\\"expected handshake response status code 101 but got 200\\\""
\t}
\treturn out
}"""
if weak_old in t:
    t = t.replace(weak_old, weak_new, 1)

if '"net"' not in t.split("import (", 1)[1].split(")", 1)[0]:
    t = t.replace('"io"\n', '"io"\n\t"net"\n', 1)

if "olc-jitsi-preflight-v4" not in t:
    t = t.replace("/* olc-jitsi-preflight-v3 */", "/* olc-jitsi-preflight-v3 */\n/* olc-jitsi-preflight-v4 */", 1)

p.write_text(t)
print("[patch-jitsi-preflight-v4] ok")
PY
