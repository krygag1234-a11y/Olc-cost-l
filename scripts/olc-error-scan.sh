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
        "created_at": now,
        "read": False,
    }
    seen[fp] = n
    notifications.append(n)

notifications.sort(key=lambda x: x.get("created_at", ""), reverse=True)
Path(out_path).write_text(json.dumps(notifications, ensure_ascii=False, indent=2))
Path(state_path).write_text(json.dumps({"seen": seen, "dismissed": list(dismissed)}, ensure_ascii=False, indent=2))
PY
