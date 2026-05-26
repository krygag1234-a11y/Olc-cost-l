#!/usr/bin/env bash
# Show installed release from version.json + link to GitHub releases page.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-releases-ui-v2' "$MAIN_TSX" && { echo "[patch-panel-releases-ui-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

blocks = [
    (
        '''              <div className="mt-1 text-muted-foreground">
                Релиз стека:{" "}
                {status?.latest_release_tag ? (
                  <code>{String(status.latest_release_tag)}</code>
                ) : (
                  <span className="text-amber-400">не определён (git fetch / rate-limit GitHub API)</span>
                )}
              </div>''',
        '''              <div className="mt-1 text-muted-foreground">
                Релиз стека (установлен):{" "}
                {(status?.installed_release_tag ?? status?.latest_release_tag) ? (
                  <code>{String(status?.installed_release_tag ?? status?.latest_release_tag)}</code>
                ) : (
                  <span className="text-amber-400">нет в version.json</span>
                )}
              </div>
              {status?.latest_release_tag &&
                status?.installed_release_tag &&
                String(status.latest_release_tag) !== String(status.installed_release_tag) && (
                  <div className="mt-1 text-xs text-emerald-400">
                    На GitHub новее: <code>{String(status.latest_release_tag)}</code>
                  </div>
                )}
              <div className="mt-1 text-[10px]">
                <a
                  className="text-primary underline"
                  href="https://github.com/krygag1234-a11y/Olc-cost-l/releases"
                  target="_blank"
                  rel="noreferrer"
                >
                  github.com/.../Olc-cost-l/releases
                </a>
              </div>''',
    ),
    (
        '''              <div className="mt-1 text-muted-foreground">
                Релиз стека (установлен):{" "}
                {status?.latest_release_tag ? (
                  <code>{String(status.latest_release_tag)}</code>
                ) : (
                  <span className="text-amber-400">не определён (git fetch / rate-limit GitHub API)</span>
                )}
              </div>''',
        '''              <div className="mt-1 text-muted-foreground">
                Релиз стека (установлен):{" "}
                {(status?.installed_release_tag ?? status?.latest_release_tag) ? (
                  <code>{String(status?.installed_release_tag ?? status?.latest_release_tag)}</code>
                ) : (
                  <span className="text-amber-400">нет в version.json</span>
                )}
              </div>
              {status?.latest_release_tag &&
                status?.installed_release_tag &&
                String(status.latest_release_tag) !== String(status.installed_release_tag) && (
                  <div className="mt-1 text-xs text-emerald-400">
                    На GitHub новее: <code>{String(status.latest_release_tag)}</code>
                  </div>
                )}
              <div className="mt-1 text-[10px]">
                <a
                  className="text-primary underline"
                  href="https://github.com/krygag1234-a11y/Olc-cost-l/releases"
                  target="_blank"
                  rel="noreferrer"
                >
                  github.com/.../Olc-cost-l/releases
                </a>
              </div>''',
    ),
]

ok = False
for old, new in blocks:
    if old in t:
        t = t.replace(old, new, 1)
        ok = True
        break

if not ok:
    print("[patch-panel-releases-ui-v2] release block not found", file=sys.stderr)
    sys.exit(1)

if '/* olc-releases-ui-v2 */' not in t:
    t = t.replace('/* olc-project-ui-v2 */', '/* olc-project-ui-v2 */\n/* olc-releases-ui-v2 */', 1)

p.write_text(t)
print("[patch-panel-releases-ui-v2] ok")
PY
