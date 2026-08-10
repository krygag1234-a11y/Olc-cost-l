#!/usr/bin/env bash
# Scan logs against data/error-catalog.json → /var/lib/olcrtc/notifications.json
set -euo pipefail

REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
CATALOG="${OLC_ERROR_CATALOG:-$REPO_ROOT/data/error-catalog.json}"
OUT="${OLC_NOTIFICATIONS_PATH:-/var/lib/olcrtc/notifications.json}"
STATE="${OLC_NOTIFICATIONS_STATE_PATH:-/var/lib/olcrtc/notifications-state.json}"
MAX_LINES="${OLC_ERROR_SCAN_MAX_LINES:-400}"

install -d "$(dirname "$OUT")" "$(dirname "$STATE")"
[[ -f "$CATALOG" ]] || { echo "[]" >"$OUT"; exit 0; }

_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# shellcheck disable=SC2016
python3 - "$CATALOG" "$OUT" "$STATE" "$MAX_LINES" <<'PY'
import json, re, hashlib, sys
from pathlib import Path
from datetime import datetime, timezone

catalog_path, out_path, state_path, max_lines = sys.argv[1:5]
max_lines = int(max_lines)

def load_json(p, default):
    try:
        return json.loads(Path(p).read_text())
    except Exception:
        return default

catalog = load_json(catalog_path, {"entries": []})
state = load_json(state_path, {"seen": {}, "dismissed": []})
seen = state.get("seen", {})
dismissed = set(state.get("dismissed", []))

sources = {
    "instance": ["/var/log/olcrtc"],
    "olcrtc": ["/var/log/olcrtc"],
    "tor": ["/var/log/tor", "/var/log/syslog"],
    "zapret": ["/var/log/zapret", "/var/log/syslog", "/var/log/olcrtc-zapret-sync.log"],
    "panel": ["/var/log/olcrtc-manager.log", "/var/log/olcrtc-feature-restart.log"],
    "split": ["/var/log/olcrtc-zapret-sync.log", "/var/log/syslog"],
}

def tail_file(path, n):
    p = Path(path)
    if not p.is_file():
        return ""
    try:
        lines = p.read_text(errors="replace").splitlines()
        return "\n".join(lines[-n:])
    except Exception:
        return ""

def gather_text(src_list):
    chunks = []
    for src in src_list:
        if Path(src).is_dir():
            for f in sorted(Path(src).glob("*.log"))[-5:]:
                chunks.append(tail_file(f, max_lines))
        else:
            chunks.append(tail_file(src, max_lines))
    return "\n".join(chunks)

notifications = []
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

for entry in catalog.get("entries", []):
    eid = entry.get("id", "")
    if not eid or eid in dismissed:
        continue
    pat = entry.get("pattern", "")
    if not pat:
        continue
    try:
        rx = re.compile(pat, re.I)
    except re.error:
        continue
    src_names = entry.get("sources", ["instance"])
    hay = ""
    for s in src_names:
        hay += gather_text(sources.get(s, sources["instance"])) + "\n"
    if not rx.search(hay):
        continue
    matched = []
    for line in hay.splitlines():
        if rx.search(line):
            matched.append(line[:240])
            if len(matched) >= 8:
                break
    fp = hashlib.sha256((eid + pat).encode()).hexdigest()[:16]
    if seen.get(fp):
        notifications.append(seen[fp])
        continue
    n = {
        "id": fp,
        "catalog_id": eid,
        "severity": entry.get("severity", "warning"),
        "title": entry.get("title", eid),
        "meaning": entry.get("meaning", ""),
        "fixes": entry.get("fixes", []),
        "matched_lines": matched,
        "created_at": now,
        "read": False,
    }
    seen[fp] = n
    notifications.append(n)

notifications.sort(key=lambda x: x.get("created_at", ""), reverse=True)
Path(out_path).write_text(json.dumps(notifications, ensure_ascii=False, indent=2))
Path(state_path).write_text(json.dumps({"seen": seen, "dismissed": list(dismissed)}, ensure_ascii=False, indent=2))
PY
# Validate config.json room_id per carrier (panel rules)
CONFIG="${OLCRTC_CONFIG:-/etc/olcrtc-manager/config.json}"
export OLC_CONFIG_PATH="$CONFIG"
python3 - "$CONFIG" "$OUT" "$STATE" <<'CFGPY' || true
import json, re, hashlib, sys
from pathlib import Path
from datetime import datetime, timezone

config_path, out_path, state_path = sys.argv[1:4]
cfg_p = Path(config_path)
if not cfg_p.is_file():
    sys.exit(0)

def load_json(p, default):
    try:
        return json.loads(Path(p).read_text())
    except Exception:
        return default

def validate_room(rid, carrier):
    rid = (rid or "").strip()
    if not rid:
        return "пустой room_id"
    if any(ord(ch) > 127 for ch in rid):
        return "не-латиница в room_id"
    c = (carrier or "jitsi").strip().lower()
    if c == "jitsi":
        if rid.startswith("http://") or rid.startswith("https://"):
            return None
        if "." in rid and " " not in rid:
            return None
        return "нужна ссылка meet (jitsi)"
    if c in ("telemost", "wbstream"):
        if rid.startswith("http://") or rid.startswith("https://"):
            return "нужен ID, не URL"
        if re.match(r"^[a-zA-Z0-9_-]+$", rid) and len(rid) <= 128:
            return None
        return "некорректный ID"
    return None

cfg = load_json(config_path, {})
clients = cfg.get("clients") or []
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
notifications = load_json(out_path, [])
state = load_json(state_path, {"seen": {}, "dismissed": []})
seen = state.get("seen", {})
dismissed = set(state.get("dismissed", []))

for ci, cl in enumerate(clients):
    cid = cl.get("client-id") or f"client-{ci}"
    for li, loc in enumerate(cl.get("locations") or []):
        endpoint = loc.get("endpoint") or {}
        room_id = endpoint.get("room_id")
        err = validate_room(room_id, loc.get("carrier"))
        if not err:
            continue
        eid = f"config-room-{cid}-{loc.get('name') or li}"
        if eid in dismissed:
            continue
        fp = hashlib.sha256(eid.encode()).hexdigest()[:16]
        n = seen.get(fp) or {
            "id": fp,
            "catalog_id": eid,
            "severity": "warning",
            "title": f"Локация {cid}: {err}",
            "meaning": f"carrier={loc.get('carrier')} room_id={room_id!r}",
            "fixes": ["Исправьте room_id в панели", "Jitsi — URL meet; telemost/wbstream — только ID"],
            "matched_lines": [],
            "created_at": now,
            "read": False,
        }
        seen[fp] = n
        if n not in notifications:
            notifications.append(n)

notifications.sort(key=lambda x: x.get("created_at", ""), reverse=True)
Path(out_path).write_text(json.dumps(notifications, ensure_ascii=False, indent=2))
Path(state_path).write_text(json.dumps({"seen": seen, "dismissed": list(dismissed)}, ensure_ascii=False, indent=2))
CFGPY
# Reconcile the current scan with persistent event history. Active issues are
# separated from resolved events while keeping the legacy JSON files/API.
python3 - "$OUT" "$STATE" <<'EVENTPY'
import json, os, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

out_path, state_path = sys.argv[1:3]
now_dt = datetime.now(timezone.utc)
now = now_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
ttl_seconds = int(os.environ.get("OLC_RESOLVED_EVENT_TTL", "604800"))

def load_json(path, default):
    try:
        return json.loads(Path(path).read_text())
    except Exception:
        return default

def parse_time(value):
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except Exception:
        return None

current_list = load_json(out_path, [])
state = load_json(state_path, {"seen": {}, "dismissed": []})
seen = state.get("seen") if isinstance(state.get("seen"), dict) else {}
dismissed = state.get("dismissed") if isinstance(state.get("dismissed"), list) else []
current = {}

for raw in current_list if isinstance(current_list, list) else []:
    if not isinstance(raw, dict) or not raw.get("id"):
        continue
    event_id = str(raw["id"])
    previous = seen.get(event_id) if isinstance(seen.get(event_id), dict) else {}
    was_active = previous.get("active", previous.get("status") != "resolved")
    event = dict(previous)
    event.update(raw)
    event["status"] = "active"
    event["active"] = True
    event["first_seen"] = previous.get("first_seen") or previous.get("created_at") or raw.get("created_at") or now
    event["created_at"] = event["first_seen"]
    event["last_seen"] = now
    event["repeat_count"] = int(previous.get("repeat_count") or 0) + 1
    event.pop("resolved_at", None)
    if not was_active:
        event["read"] = False
    current[event_id] = event

resolved = {}
for event_id, raw in seen.items():
    if event_id in current or not isinstance(raw, dict):
        continue
    event = dict(raw)
    if event.get("active", event.get("status") != "resolved"):
        event["status"] = "resolved"
        event["active"] = False
        event["resolved_at"] = now
        event["read"] = False
    resolved_at = parse_time(event.get("resolved_at"))
    if resolved_at is None or now_dt - resolved_at <= timedelta(seconds=ttl_seconds):
        resolved[event_id] = event

merged = {**resolved, **current}
visible = [
    event for event in merged.values()
    if event.get("id") not in dismissed and event.get("catalog_id") not in dismissed
]
visible.sort(key=lambda event: (bool(event.get("active")), event.get("last_seen") or event.get("resolved_at") or event.get("created_at") or ""), reverse=True)
Path(out_path).write_text(json.dumps(visible, ensure_ascii=False, indent=2))
Path(state_path).write_text(json.dumps({"schema": 2, "seen": merged, "dismissed": dismissed}, ensure_ascii=False, indent=2))
EVENTPY
