#!/usr/bin/env bash
# Panel UI: send link=tor on create; only config link=direct skips SOCKS on server.
set -euo pipefail
PANEL="${1:-}"
[[ -z "$PANEL" ]] && PANEL="${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx"
[[ -f "$PANEL" ]] || { echo "[patch-manager-panel-link] skip: no $PANEL"; exit 0; }

python3 - "$PANEL" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
if 'link: "tor"' in t and "location.link?.trim()" in t:
    print("[patch-manager-panel-link] already patched"); raise SystemExit(0)
    raise SystemExit(0)

if "link?: string;" not in t:
    t = t.replace(
        "  dns: string;\n};\n\ntype ClientForm",
        "  dns: string;\n  link?: string;\n};\n\ntype ClientForm",
        1,
    )

t = t.replace(
    '  dns: "1.1.1.1:53",\n};',
    '  dns: "1.1.1.1:53",\n  link: "tor",\n};',
    1,
)

if "location.link?.trim()" not in t:
    old = """  return {
    ...location,
    transport,
    payload,
  };
}"""
    new = """  const link = (location.link?.trim() || "tor").toLowerCase();
  return {
    ...location,
    transport,
    payload,
    link: link === "direct" ? "direct" : "tor",
  };
}"""
    if old not in t:
        print("patch-manager-panel-link: normalizeLocationForm block not found"); raise SystemExit(0)
    t = t.replace(old, new, 1)

if "link: (location.link" not in t:
    t = t.replace(
        "    dns: location.dns.trim(),\n  }));",
        "    dns: location.dns.trim(),\n    link: (location.link?.trim() || \"tor\").toLowerCase(),\n  }));",
        1,
    )

if "link: location.link," not in t:
    t = t.replace(
        "        dns: location.dns,\n      }),",
        "        dns: location.dns,\n        link: location.link,\n      }),",
        1,
    )

p.write_text(t)
print("[patch-manager-panel-link] ok"); raise SystemExit(0)
PY
