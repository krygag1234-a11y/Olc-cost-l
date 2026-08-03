#!/usr/bin/env bash
# Keep new Jitsi forms empty/editable and separate HTTPS discovery from Server/Room fields.
set -euo pipefail

target="${1:-/tmp/olcrtc-manager-panel/src/main.tsx}"
[[ -f "$target" ]] || { echo "[jitsi-form-layout] target not found: $target" >&2; exit 1; }

python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "OLC_JITSI_FORM_LAYOUT_V1"
if marker in text:
    print(f"[jitsi-form-layout] already applied: {path}")
    raise SystemExit(0)

def one(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"[jitsi-form-layout] {label}: expected one match, got {count}")
    text = text.replace(old, new, 1)

if text.count('  jitsi_instance: DEFAULT_JITSI_INSTANCE,') != 2:
    raise SystemExit("[jitsi-form-layout] Jitsi defaults changed")
text = text.replace('  jitsi_instance: DEFAULT_JITSI_INSTANCE,', '  jitsi_instance: "",')
one('  if (!server) return DEFAULT_JITSI_INSTANCE;', '  if (!server) return "";', "empty normalizer")
one(
'''  for (const loc of locations) {
    const roomID = loc.carrier === "jitsi" ? jitsiRoomForSubmit(loc) : loc.room_id;''',
'''  for (const loc of locations) {
    if (loc.carrier === "jitsi" && !loc.jitsi_instance.trim()) {
      throw new Error("Укажите Jitsi Server");
    }
    const roomID = loc.carrier === "jitsi" ? jitsiRoomForSubmit(loc) : loc.room_id;''',
"required server",
)
one(
'  const valueForValidation = carrier === "jitsi" ? combineJitsiRoomId(jitsiServer || DEFAULT_JITSI_INSTANCE, value) : value;',
'  const valueForValidation = carrier === "jitsi" ? combineJitsiRoomId(jitsiServer || "", value) : value;',
"room validation",
)

component_start = text.index("function JitsiHTTPSDiscovery(")
component_end = text.index("\n\nfunction roomPlaceholder", component_start)
old_component = text[component_start:component_end]
new_component = old_component
new_component = new_component.replace(
    'function JitsiHTTPSDiscovery({ server, onUse }: { server: string; onUse: (server: string) => void }) {',
    'function JitsiHTTPSDiscovery({ onUse }: { onUse: (server: string) => void }) {\n  const [source, setSource] = useState("");',
)
new_component = new_component.replace("numericJitsiIP(server)", "numericJitsiIP(source)")
new_component = new_component.replace("}, [server]);", "}, [source]);")
new_component = new_component.replace("encodeURIComponent(server.trim())", "encodeURIComponent(source.trim())")
new_component = new_component.replace("}, [ip, server]);", "}, [ip, source]);")
new_component = new_component.replace("\n  if (!ip) return null;", "")
new_component = new_component.replace(
'''      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <div className="font-medium text-foreground">Помощник Jitsi HTTP IP → HTTPS domain:443</div>
          <div className="mt-0.5 text-[11px] text-muted-foreground">Проверяет DNS, Jitsi endpoints и доверие TLS. Домены с просроченным/недоверенным сертификатом показываются отдельно и требуют insecure TLS.</div>
        </div>
        <button
          type="button"
          className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted disabled:opacity-50"
          disabled={busy}
          onClick={() => void discover()}
        >
          {busy ? "Проверяю…" : "Найти HTTPS-домен"}
        </button>
      </div>''',
'''      <div className="grid gap-2">
        <div>
          <div className="font-medium text-foreground">Помощник Jitsi HTTP IP → HTTPS-домен</div>
          <div className="mt-0.5 text-[11px] text-muted-foreground">Проверяет DNS, Jitsi endpoints и доверие TLS. Домены с просроченным/недоверенным сертификатом показываются отдельно и требуют insecure TLS.</div>
        </div>
        <div className="flex gap-2">
          <input
            className="h-9 min-w-0 flex-1 rounded-md border border-border bg-card px-3 font-mono text-xs text-foreground outline-none focus:border-primary"
            value={source}
            onChange={(event) => setSource(event.target.value)}
            placeholder="HTTP IP Jitsi, например 185.16.214.115"
          />
          <button
            type="button"
            className="inline-flex h-9 shrink-0 items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted disabled:opacity-50"
            disabled={busy || !ip}
            onClick={() => void discover()}
          >
            {busy ? "Проверяю…" : "Найти HTTPS-домен"}
          </button>
        </div>
      </div>''',
)
if new_component == old_component or "value={source}" not in new_component:
    raise SystemExit("[jitsi-form-layout] discovery component changed")
text = text[:component_start] + new_component + text[component_end:]

one(
'''    } else if (!normalized.jitsi_instance?.trim()) {
      normalized.jitsi_instance = DEFAULT_JITSI_INSTANCE;
''',
''' '''.strip(),
"blank fallback",
)
first_start = text.index('      {location.carrier === "jitsi" ? (', text.index("function LocationFormFields"))
first_end = text.index('      <label className="grid gap-2 text-sm text-muted-foreground">\n        Key', first_start)
text = text[:first_start] + '''      {location.carrier === "jitsi" ? (
        <div className="grid gap-3 text-sm text-muted-foreground">
          <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(260px,0.65fr)]">
            <label className="grid gap-2">
              Jitsi Server
              <input className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary" value={location.jitsi_instance} onChange={(event) => set({ jitsi_instance: event.target.value })} placeholder={DEFAULT_JITSI_INSTANCE} />
            </label>
            <label className="grid gap-2">
              Room ID
              <RoomIDInput value={location.room_id} carrier={location.carrier} jitsiServer={location.jitsi_instance} onChange={(room_id) => set({ room_id })} />
            </label>
          </div>
          <p className="text-[11px] text-muted-foreground">Можно вставить полную ссылку сюда или в Room ID — поля разделятся автоматически.</p>
          <JitsiHTTPSDiscovery onUse={(jitsi_instance) => set({ jitsi_instance })} />
          <JitsiPreflightNotice carrier={location.carrier} roomID={jitsiRoomForSubmit(location)} />
        </div>
      ) : (
        <label className="grid gap-2 text-sm text-muted-foreground">
          Room ID
          <RoomIDInput value={location.room_id} carrier={location.carrier} onChange={(room_id) => set({ room_id })} />
          <p className="text-[11px] text-muted-foreground">Telemost / WB Stream: только ID комнаты (цифры и латиница), без https://</p>
        </label>
      )}
''' + text[first_end:]

second_start = text.index('            {location.carrier === "jitsi" ? (', text.index("function ClientFormFields"))
second_end = text.index('            <label className="grid gap-2 text-sm text-muted-foreground">\n              Key', second_start)
text = text[:second_start] + '''            {location.carrier === "jitsi" ? (
              <div className="grid gap-3 text-sm text-muted-foreground">
                <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(260px,0.65fr)]">
                  <label className="grid gap-2">
                    Jitsi Server
                    <input className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary" value={location.jitsi_instance} onChange={(event) => setLocation(index, { jitsi_instance: event.target.value })} placeholder={DEFAULT_JITSI_INSTANCE} />
                  </label>
                  <label className="grid gap-2">
                    Room ID
                    <RoomIDInput value={location.room_id} carrier={location.carrier} jitsiServer={location.jitsi_instance} onChange={(room_id) => setLocation(index, { room_id })} inputClassName="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary" />
                  </label>
                </div>
                <p className="text-[11px] text-muted-foreground">Полную ссылку можно вставить в любое из двух полей.</p>
                <JitsiHTTPSDiscovery onUse={(jitsi_instance) => setLocation(index, { jitsi_instance })} />
              </div>
            ) : (
              <label className="grid gap-2 text-sm text-muted-foreground">
                Room ID
                <RoomIDInput value={location.room_id} carrier={location.carrier} onChange={(room_id) => setLocation(index, { room_id })} inputClassName="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary" />
              </label>
            )}
''' + text[second_end:]

one(
'''      for (const loc of locs) {
        const re = validateRoomIDInput(loc.room_id, loc.carrier);
        if (re) throw new Error(re);
      }''',
'''      assertLocationsValid(locs);''',
"create client validation",
)
one(
'''    const roomErr = validateRoomIDInput(prepared.room_id, prepared.carrier);''',
'''    const roomErr = prepared.carrier === "jitsi" && !prepared.jitsi_instance.trim()
      ? "Укажите Jitsi Server"
      : validateRoomIDInput(prepared.carrier === "jitsi" ? jitsiRoomForSubmit(prepared) : prepared.room_id, prepared.carrier);''',
"create location validation",
)

text = text.replace("/* OLC_JITSI_HTTPS_DISCOVERY_UI_V1 */", "/* OLC_JITSI_HTTPS_DISCOVERY_UI_V1 */\n/* OLC_JITSI_FORM_LAYOUT_V1 */", 1)
path.write_text(text)
print(f"[jitsi-form-layout] applied: {path}")
PY
