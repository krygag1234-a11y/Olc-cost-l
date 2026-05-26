#!/usr/bin/env bash
# Project modal: human flag labels, stack manifest, stale update hint, channel pre-alpha.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-project-ui-v2' "$MAIN_TSX" && { echo "[patch-panel-project-ui-v2] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# version card: show channel
t = t.replace(
    '<div className="text-xs text-muted-foreground">профиль: {String(status?.deploy_profile ?? "—")}</div>',
    '<div className="text-xs text-muted-foreground">канал: {String(status?.channel ?? "—")} · профиль: {String(status?.deploy_profile ?? "—")}</div>',
    1,
)

# git / release block — replace releases-ui block if present or old line
release_old = '''              <div className="mt-1 text-muted-foreground">
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

release_new = '''              <div className="mt-1 text-muted-foreground">
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
              </div>
              {Boolean(status?.git_ahead) && (
                <p className="mt-1 text-amber-400">Локальный репозиторий впереди origin/main</p>
              )}
              {Boolean(status?.update_available) && (
                <p className="mt-1 text-emerald-400">
                  {status?.update_source === "release"
                    ? `Доступен релиз ${String(status?.latest_release_tag ?? "")}`
                    : "Доступно обновление origin/main"}
                </p>
              )}'''

if release_old in t:
    t = t.replace(release_old, release_new, 1)
elif '{Boolean(status?.update_available) && <p className="mt-1 text-emerald-400">Доступно обновление origin/main</p>}' in t:
    t = t.replace(
        '{Boolean(status?.update_available) && <p className="mt-1 text-emerald-400">Доступно обновление origin/main</p>}',
        release_new,
        1,
    )

flags_old = '''            <div className="rounded border border-border p-3 text-xs">
              <div className="mb-1 font-medium">Компоненты (флаги)</div>
              <div className="flex flex-wrap gap-2">
                {Object.entries(caps.flags ?? {}).map(([k, v]) => (
                  <span key={k} className={`rounded px-2 py-0.5 ${v ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-500/20"}`}>
                    {k}: {v ? "on" : "off"}
                  </span>
                ))}
              </div>
            </div>'''

flags_new = '''            <div className="rounded border border-border p-3 text-xs">
              <div className="mb-1 font-medium">Компоненты (флаги features.env)</div>
              <div className="flex flex-wrap gap-2">
                {(
                  [
                    ["zapret", "Zapret"],
                    ["tor", "Tor"],
                    ["split", "Split"],
                    ["bridges", "Мосты"],
                    ["warp", "WARP"],
                    ["olcrtc", "OlcRTC"],
                  ] as const
                ).map(([k, label]) => {
                  const v = Boolean((caps.flags as Record<string, boolean> | undefined)?.[k]);
                  return (
                    <span key={k} className={`rounded px-2 py-0.5 ${v ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-500/20"}`}>
                      {label}: {v ? "on" : "off"}
                    </span>
                  );
                })}
              </div>
            </div>
            {(status?.stack_manifest as Record<string, unknown> | undefined) && (
              <div className="rounded border border-border p-3 text-xs">
                <div className="mb-1 font-medium">Состав релиза (upstream pins)</div>
                <ul className="space-y-1 font-mono text-[10px] text-muted-foreground">
                  {Object.entries(status.stack_manifest as Record<string, { ref?: string; branch?: string; source?: string; channel?: string }>).map(([name, meta]) => (
                    <li key={name}>
                      {name}:{" "}
                      {meta.ref ? <span>{String(meta.ref).slice(0, 12)}</span> : null}
                      {meta.branch ? <span> ({meta.branch})</span> : null}
                      {meta.source ? <span> · {meta.source}</span> : null}
                      {meta.channel ? <span> · {meta.channel}</span> : null}
                    </li>
                  ))}
                </ul>
                <p className="mt-1 text-[10px] text-muted-foreground">webtunnel-client — бинарь с mirror-cry, не из olcrtc gitlab</p>
              </div>
            )}'''

if flags_old in t:
    t = t.replace(flags_old, flags_new, 1)

stale_old = '''            {(job?.status === "running" || status?.update_locked) && (
              <p className="text-amber-400">Обновление выполняется… не закрывайте вкладку до перезапуска панели.</p>
            )}'''

stale_new = '''            {Boolean(status?.update_locked) && (
              <p className="text-amber-400">Обновление выполняется… не закрывайте вкладку до перезапуска панели.</p>
            )}
            {!status?.update_locked && job?.status === "running" && (
              <p className="text-amber-400">Прошлое обновление зависло — нажмите «Обновить с GitHub» ещё раз.</p>
            )}
            {job?.status === "failed" && job?.error ? (
              <p className="text-destructive text-xs">{String(job.error)}</p>
            ) : null}'''

if stale_old in t:
    t = t.replace(stale_old, stale_new, 1)

if '/* olc-project-ui-v2 */' not in t:
    t = t.replace('/* olc-releases-ui */', '/* olc-releases-ui */\n/* olc-project-ui-v2 */', 1)

p.write_text(t)
print("[patch-panel-project-ui-v2] ok")
PY
