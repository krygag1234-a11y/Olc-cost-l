#!/usr/bin/env bash
# Hotfix v22: room_id — URL только для jitsi; telemost/wbstream/jazz — ID комнаты.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-manager-hotfix-v22-room' "$MAIN_GO" && { echo "[patch-manager-hotfix-v22-room] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

new_fn = r'''func validateRoomIDStrict(roomID, carrier string) error {
	roomID = strings.TrimSpace(roomID)
	if roomID == "" || roomID == "any" {
		return errors.New("room_id обязателен")
	}
	for _, r := range roomID {
		if r > 127 {
			return errors.New("room_id: только латиница и цифры")
		}
	}
	carrier = strings.TrimSpace(strings.ToLower(carrier))
	if carrier == "" {
		carrier = "jitsi"
	}
	rid := roomID
	if carrier == "jitsi" {
		if strings.HasPrefix(rid, "http://") || strings.HasPrefix(rid, "https://") {
			if _, err := url.Parse(rid); err != nil {
				return fmt.Errorf("room_id: некорректный URL Jitsi: %w", err)
			}
			return nil
		}
		if strings.Contains(rid, ".") && !strings.Contains(rid, " ") {
			return nil
		}
		return errors.New("room_id: для Jitsi укажите https://meet.example.com/room или meet.example.com/room")
	}
	if carrier == "telemost" || carrier == "wbstream" || carrier == "jazz" {
		if strings.HasPrefix(rid, "http://") || strings.HasPrefix(rid, "https://") {
			return errors.New("room_id: для этого провайдера укажите ID комнаты, не ссылку")
		}
		for _, ch := range rid {
			if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' {
				continue
			}
			return errors.New("room_id: некорректный ID (латиница, цифры, _ и -)")
		}
		if len(rid) < 1 || len(rid) > 128 {
			return errors.New("room_id: длина ID 1–128 символов")
		}
		return nil
	}
	return nil
}
'''

pat = re.compile(r"func validateRoomIDStrict\(roomID, carrier string\) error \{[\s\S]*?\n\}\n\nfunc sanitizeConfigInvalidLocations", re.M)
m = pat.search(t)
if not m:
    print("[patch-manager-hotfix-v22-room] validateRoomIDStrict block not found", file=sys.stderr)
    sys.exit(1)
t = t[: m.start()] + new_fn + "\n\nfunc sanitizeConfigInvalidLocations" + t[m.end() :]

if "olc-manager-hotfix-v22-room" not in t:
    if "olc-manager-hotfix-v21" in t:
        t = t.replace("olc-manager-hotfix-v21", "olc-manager-hotfix-v21\n/* olc-manager-hotfix-v22-room */", 1)
    else:
        t = "/* olc-manager-hotfix-v22-room */\n" + t

p.write_text(t)
print("[patch-manager-hotfix-v22-room] ok")
PY
