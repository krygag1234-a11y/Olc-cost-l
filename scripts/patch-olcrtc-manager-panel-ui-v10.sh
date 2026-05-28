#!/usr/bin/env bash
# UI v10: project mini-charts + full olcrtc settings form.
set -euo pipefail
MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'olc-panel-ui-v10' "$MAIN_TSX" && { echo "[patch-panel-ui-v10] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
t = t.replace("/* olc-panel-ui-v9 */", "/* olc-panel-ui-v10 */", 1) if "olc-panel-ui-v9" in t else t.replace(
    "import React, {", "/* olc-panel-ui-v10 */\nimport React, {", 1
)

old_olcrtc = '''            {feature === "olcrtc" && (
              <>
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.jitsi_insecure_tls)} onChange={(e) => setBool("jitsi_insecure_tls", e.target.checked)} />
                  OLCRTC_JITSI_INSECURE_TLS (самоподписанные сертификаты Jitsi)
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Публичный URL панели (OLCRTC_PUBLIC_URL)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.public_url ?? "")} onChange={(e) => setStr("public_url", e.target.value)} placeholder="https://vps.example:8888" />
                </label>
                <p className="text-xs text-muted-foreground">Ветка: fix/all · pin: <code>{String(settings.olcrtc_pinned_sha ?? "").slice(0, 12) || "—"}</code></p><p className="text-xs text-muted-foreground">После сохранения — olc-update или перезапуск инстансов.</p>
              </>
            )}'''

new_olcrtc = '''            {feature === "olcrtc" && (
              <>
                <label className="flex items-center gap-2 text-xs">
                  <input type="checkbox" checked={Boolean(settings.jitsi_insecure_tls)} onChange={(e) => setBool("jitsi_insecure_tls", e.target.checked)} />
                  OLCRTC_JITSI_INSECURE_TLS (самоподписанные сертификаты Jitsi)
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Публичный URL панели (OLCRTC_PUBLIC_URL)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.public_url ?? "")} onChange={(e) => setStr("public_url", e.target.value)} placeholder="https://vps.example:8888" />
                </label>
                <div className="grid gap-2 md:grid-cols-2">
                  <label className="grid gap-1 text-muted-foreground">
                    Default carrier
                    <select className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.default_carrier ?? "")} onChange={(e) => setStr("default_carrier", e.target.value)}>
                      <option value="">(не задан)</option>
                      <option value="jitsi">jitsi</option>
                      <option value="wbstream">wbstream</option>
                      <option value="telemost">telemost</option>
                      <option value="jazz">jazz</option>
                    </select>
                  </label>
                  <label className="grid gap-1 text-muted-foreground">
                    Default transport
                    <select className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.default_transport ?? "")} onChange={(e) => setStr("default_transport", e.target.value)}>
                      <option value="">(не задан)</option>
                      <option value="datachannel">datachannel</option>
                      <option value="vp8channel">vp8channel</option>
                      <option value="seichannel">seichannel</option>
                      <option value="videochannel">videochannel</option>
                    </select>
                  </label>
                </div>
                <label className="grid gap-1 text-muted-foreground">
                  Default link
                  <select className="h-9 rounded-md border border-border bg-background px-2 text-xs" value={String(settings.default_link ?? "")} onChange={(e) => setStr("default_link", e.target.value)}>
                    <option value="">(не задан)</option>
                    <option value="tor">tor</option>
                    <option value="direct">direct</option>
                  </select>
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  SOCKS proxy (optional)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.socks_proxy ?? "")} onChange={(e) => setStr("socks_proxy", e.target.value)} placeholder="user:pass@host:port" />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  WARP proxy (optional)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.warp_proxy ?? "")} onChange={(e) => setStr("warp_proxy", e.target.value)} placeholder="127.0.0.1:40000" />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  Tor signaling proxy (optional)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.tor_proxy ?? "")} onChange={(e) => setStr("tor_proxy", e.target.value)} placeholder="user:pass@host:port" />
                </label>
                <label className="grid gap-1 text-muted-foreground">
                  WebRTC signaling proxy (optional)
                  <input className="h-9 rounded-md border border-border bg-background px-2 text-xs font-mono" value={String(settings.webrtc_proxy ?? "")} onChange={(e) => setStr("webrtc_proxy", e.target.value)} placeholder="user:pass@host:port" />
                </label>
                <p className="text-xs text-muted-foreground">Ветка: fix/all · pin: <code>{String(settings.olcrtc_pinned_sha ?? "").slice(0, 12) || "—"}</code></p><p className="text-xs text-muted-foreground">После сохранения — olc-update или перезапуск инстансов.</p>
              </>
            )}'''

if old_olcrtc in t:
    t = t.replace(old_olcrtc, new_olcrtc, 1)

if "className=\"mt-2 h-2 w-full overflow-hidden rounded bg-zinc-700/50\"" not in t:
    t = t.replace(
        '''                <div className="text-lg font-semibold">
                  {(stack.enabled as number) ?? 0}/{(stack.total as number) ?? 4}
                </div>''',
        '''                <div className="text-lg font-semibold">
                  {(stack.enabled as number) ?? 0}/{(stack.total as number) ?? 4}
                </div>
                <div className="mt-2 h-2 w-full overflow-hidden rounded bg-zinc-700/50">
                  <div
                    className="h-full bg-emerald-400 transition-all"
                    style={{
                      width: `${Math.max(0, Math.min(100, Math.round((((stack.enabled as number) ?? 0) / Math.max(1, ((stack.total as number) ?? 4))) * 100)))}%`,
                    }}
                  />
                </div>''',
        1,
    )
    t = t.replace(
        '''                <div className="text-xs text-muted-foreground">всего {notif.total ?? 0}, непрочит. {notif.unread ?? 0}</div>''',
        '''                <div className="text-xs text-muted-foreground">всего {notif.total ?? 0}, непрочит. {notif.unread ?? 0}</div>
                <div className="mt-2 grid grid-cols-3 gap-1 text-[10px]">
                  <div className="rounded bg-zinc-700/40 px-1 py-1 text-center">
                    <div className="text-muted-foreground">all</div>
                    <div>{notif.total ?? 0}</div>
                  </div>
                  <div className="rounded bg-amber-500/15 px-1 py-1 text-center">
                    <div className="text-muted-foreground">unread</div>
                    <div>{notif.unread ?? 0}</div>
                  </div>
                  <div className="rounded bg-red-500/15 px-1 py-1 text-center">
                    <div className="text-muted-foreground">errors</div>
                    <div>{notif.errors ?? 0}</div>
                  </div>
                </div>''',
        1,
    )

p.write_text(t)
print("[patch-panel-ui-v10] ok"); print(0); raise SystemExit(0)
PY
