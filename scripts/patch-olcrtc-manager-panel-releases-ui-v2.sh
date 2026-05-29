#!/usr/bin/env bash
# Show installed release from version.json + link to GitHub releases page.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-releases-ui-v2' "$MAIN_TSX" && grep -q 'installed_release_tag' "$MAIN_TSX" && { echo "[patch-panel-releases-ui-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

release_block = '''              <div className="mt-1 text-muted-foreground">
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
              </div>'''

blocks = [
    (
        '''              {Boolean(status?.update_available) && <p className="mt-1 text-emerald-400">Доступно обновление origin/main</p>}''',
        release_block + '''
              {Boolean(status?.git_ahead) && (
                <p className="mt-1 text-amber-400">Локальный репозиторий впереди origin/main</p>
              )}
              {Boolean(status?.update_available) && (
                <p className="mt-1 text-emerald-400">
                  {status?.update_source === "release"
                    ? `Доступен релиз ${String(status?.latest_release_tag ?? "")}`
                    : "Доступно обновление origin/main"}
                </p>
              )}''',
    ),
    (
        '''              <div className="mt-1 text-muted-foreground">
                GitHub release:{" "}
                {status?.latest_release_tag ? (
                  <code>{String(status.latest_release_tag)}</code>
                ) : (
                  <span className="text-amber-400">ещё нет — проверка по origin/main</span>
                )}
              </div>''',
        release_block,
    ),
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
    print("[patch-panel-releases-ui-v2] release block not found", file=sys.stderr); raise SystemExit(0)
    sys.exit(1)

if '/* olc-releases-ui-v2 */' not in t:
    t = t.replace('/* olc-project-ui-v2 */', '/* olc-project-ui-v2 */\n/* olc-releases-ui-v2 */', 1)

p.write_text(t)
print("[patch-panel-releases-ui-v2] ok"); raise SystemExit(0)
PY
