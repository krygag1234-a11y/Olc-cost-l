#!/usr/bin/env bash
# Scan logs against data/error-catalog.json → /var/lib/olcrtc/notifications.json
set -euo pipefail

REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
CATALOG="${OLC_ERROR_CATALOG:-$REPO_ROOT/data/error-catalog.json}"
OUT=/var/lib/olcrtc/notifications.json
STATE=/var/lib/olcrtc/notifications-state.json
MAX_LINES=400

install -d /var/lib/olcrtc
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
    if c in ("telemost", "wbstream", "jazz"):
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
    cid = cl.get("id") or f"client-{ci}"
    for li, loc in enumerate(cl.get("locations") or []):
        err = validate_room(loc.get("room_id"), loc.get("carrier"))
        if not err:
            continue
        eid = f"config-room-{cid}-{li}"
        if eid in dismissed:
            continue
        fp = hashlib.sha256(eid.encode()).hexdigest()[:16]
        n = seen.get(fp) or {
            "id": fp,
            "catalog_id": eid,
            "severity": "warning",
            "title": f"Локация {cid}: {err}",
            "meaning": f"carrier={loc.get('carrier')} room_id={loc.get('room_id')!r}",
            "fixes": ["Исправьте room_id в панели", "Jitsi — URL meet; telemost/wbstream/jazz — только ID"],
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
