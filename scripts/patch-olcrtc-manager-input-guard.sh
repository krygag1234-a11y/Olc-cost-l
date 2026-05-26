#!/usr/bin/env bash
# Guard manager inputs: strict client_id validation and room_id normalization.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'validateClientIDStrict' "$MAIN_GO" && { echo "[patch-input-guard] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helpers = """
func validateClientIDStrict(clientID string) error {
\tclientID = strings.TrimSpace(clientID)
\tif clientID == "" {
\t\treturn errors.New("client_id is required")
\t}
\tif len(clientID) > 64 {
\t\treturn errors.New("client_id must be <= 64 chars")
\t}
\tif strings.Contains(clientID, "/") {
\t\treturn errors.New("client_id must not contain slash")
\t}
\tfor _, ch := range clientID {
\t\tif (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' {
\t\t\tcontinue
\t\t}
\t\treturn errors.New("client_id allows only a-z A-Z 0-9 _ -")
\t}
\treturn nil
}

func normalizeRoomID(roomID string) string {
\troomID = strings.TrimSpace(roomID)
\tif roomID == "" {
\t\treturn roomID
\t}
\tif strings.HasPrefix(roomID, "http://") || strings.HasPrefix(roomID, "https://") {
\t\treturn roomID
\t}
\tif strings.HasPrefix(roomID, "//") {
\t\treturn "https:" + roomID
\t}
\tif strings.Contains(roomID, ".") && !strings.Contains(roomID, " ") {
\t\treturn "https://" + roomID
\t}
\treturn roomID
}

"""

anchor = "func addClientFromRequest(ctx context.Context, configPath, olcrtcPath string, r *http.Request) (string, error) {"
if "func validateClientIDStrict" not in t:
    t = t.replace(anchor, helpers + anchor, 1)

t = t.replace(
"""	req.Quota = normalizeQuota(req.Quota)
	if req.ClientID == "" {
		return "", errors.New("client_id is required")
	}
	if strings.Contains(req.ClientID, "/") {
		return "", errors.New("client_id must not contain slash")
	}
	if err := validateQuota(req.Quota); err != nil {""",
"""	req.Quota = normalizeQuota(req.Quota)
	if err := validateClientIDStrict(req.ClientID); err != nil {
		return "", err
	}
	if err := validateQuota(req.Quota); err != nil {""",
1)

t = t.replace(
"""	if strings.Contains(nextClientID, "/") {
		return errors.New("client_id must not contain slash")
	}""",
"""	if err := validateClientIDStrict(nextClientID); err != nil {
		return err
	}""",
1)

t = t.replace(
"""	clientID = strings.TrimSpace(clientID)
	var req addClientRequest""",
"""	clientID = strings.TrimSpace(clientID)
	if err := validateClientIDStrict(clientID); err != nil {
		return err
	}
	var req addClientRequest""",
1)

t = t.replace(
"""		req.RoomID = strings.TrimSpace(req.RoomID)""",
"""		req.RoomID = normalizeRoomID(strings.TrimSpace(req.RoomID))""",
1)

p.write_text(t)
print("[patch-input-guard] ok")
PY
