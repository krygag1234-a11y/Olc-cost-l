#!/usr/bin/env bash
# Strict room_id validation + sanitize invalid locations on config load.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
if grep -q 'validateRoomIDStrict' "$MAIN_GO" && ! grep -q 'undefined: prefix' "$MAIN_GO" 2>/dev/null; then
  if grep -q 'validateRoomIDStrict(req.RoomID, req.Carrier)' "$MAIN_GO"; then
    echo "[patch-room-validate] already applied"
    exit 0
  fi
fi

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helpers = r'''
func validateRoomIDStrict(roomID, carrier string) error {
	roomID = strings.TrimSpace(roomID)
	if roomID == "" || roomID == "any" {
		return errors.New("room_id is required")
	}
	for _, r := range roomID {
		if r > 127 {
			return errors.New("room_id: используйте латинский URL (https://meet.example.com/room)")
		}
	}
	carrier = strings.TrimSpace(strings.ToLower(carrier))
	if carrier == "" {
		carrier = "jitsi"
	}
	if carrier == "jitsi" || carrier == "wbstream" || carrier == "telemost" || carrier == "jazz" {
		rid := roomID
		if strings.HasPrefix(rid, "http://") || strings.HasPrefix(rid, "https://") {
			if _, err := url.Parse(rid); err != nil {
				return fmt.Errorf("room_id: некорректный URL: %w", err)
			}
			return nil
		}
		if strings.Contains(rid, ".") && !strings.Contains(rid, " ") {
			return nil
		}
		return errors.New("room_id: укажите https://meet.example.com/room или meet.example.com/room")
	}
	return nil
}

func sanitizeConfigInvalidLocations(cfg *Config) []string {
	var warnings []string
	for i := range cfg.Clients {
		kept := cfg.Clients[i].Locations[:0]
		for _, loc := range cfg.Clients[i].Locations {
			room := normalizeRoomID(strings.TrimSpace(loc.Endpoint.RoomID))
			loc.Endpoint.RoomID = room
			if err := validateRoomIDStrict(room, loc.Carrier); err != nil {
				warnings = append(warnings, fmt.Sprintf(
					"removed invalid location for client %q (%s): %v",
					cfg.Clients[i].ClientID, loc.Name, err,
				))
				continue
			}
			kept = append(kept, loc)
		}
		cfg.Clients[i].Locations = kept
	}
	cfg.Normalize()
	return warnings
}

'''

anchor = "func validateClientIDStrict"
if "func validateRoomIDStrict" not in t:
    t = t.replace(anchor, helpers + anchor, 1)

# import net/url if missing
if '"net/url"' not in t:
    t = t.replace('"net/http"\n', '"net/http"\n\t"net/url"\n', 1)

# buildLocations: validate after prefix is defined
bad = """\t\tif err := validateRoomIDStrict(req.RoomID, req.Carrier); err != nil {
\t\t\treturn nil, fmt.Errorf("%s.room_id: %w", prefix, err)
\t\t}
\t\treq.Carrier"""
if bad in t:
    t = t.replace(bad, "\t\treq.Carrier", 1)

marker = '\t\tprefix := fmt.Sprintf("locations[%d]", i)'
insert = marker + """
\t\tif err := validateRoomIDStrict(req.RoomID, req.Carrier); err != nil {
\t\t\treturn nil, fmt.Errorf("%s.room_id: %w", prefix, err)
\t\t}"""
if "validateRoomIDStrict(req.RoomID" not in t.split("func buildLocations")[1][:1200]:
    t = t.replace(marker, insert, 1)

# loadConfig: sanitize after Normalize (signature: loadConfig(path string))
if "sanitizeConfigInvalidLocations(&cfg)" not in t:
    t = t.replace(
        """func loadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}
	cfg.Normalize()
	return cfg, nil
}""",
        """func loadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}
	cfg.Normalize()
	if warns := sanitizeConfigInvalidLocations(&cfg); len(warns) > 0 {
		for _, w := range warns {
			log.Printf("config sanitize: %s", w)
		}
		_ = saveConfig(path, cfg)
	}
	return cfg, nil
}""",
        1,
    )

p.write_text(t)
print("[patch-room-validate] ok")
PY
