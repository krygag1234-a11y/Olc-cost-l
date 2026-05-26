#!/usr/bin/env bash
# Project modal: show GitHub release tag + clearer update message.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-releases-ui' "$MAIN_TSX" && { echo "[patch-panel-releases-ui] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

old = '''              {Boolean(status?.update_available) && <p className="mt-1 text-emerald-400">Доступно обновление origin/main</p>}'''

new = '''              <div className="mt-1 text-muted-foreground">
                GitHub release:{" "}
                {status?.latest_release_tag ? (
                  <code>{String(status.latest_release_tag)}</code>
                ) : (
                  <span className="text-amber-400">ещё нет — проверка по origin/main</span>
                )}
              </div>
              {Boolean(status?.git_ahead) && (
                <p className="mt-1 text-amber-400">Локальный репозиторий впереди origin/main (есть незапушенные коммиты)</p>
              )}
              {Boolean(status?.update_available) && (
                <p className="mt-1 text-emerald-400">
                  {status?.update_source === "release"
                    ? `Доступен релиз ${String(status?.latest_release_tag ?? "")}`
                    : "Доступно обновление origin/main"}
                </p>
              )}'''

if old not in t:
    print("[patch-panel-releases-ui] git update line not found", file=sys.stderr)
    sys.exit(1)

t = t.replace(old, new, 1)
if '/* olc-releases-ui */' not in t:
    t = t.replace('/* olc-project-ui-fix */', '/* olc-project-ui-fix */\n/* olc-releases-ui */', 1)

p.write_text(t)
print("[patch-panel-releases-ui] ok")
PY
