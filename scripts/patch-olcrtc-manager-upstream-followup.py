#!/usr/bin/env python3
"""Apply the selected manager upstream follow-ups after all legacy patches.

- per-location upstream SOCKS5 fields;
- remove Jazz without disabling the experimental wbstream datachannel mode;
- split Jitsi server/room fields with smart full-URL sorting.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


MARKER = "OLC_MANAGER_UPSTREAM_FOLLOWUP_V1"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def patch_go(path: Path) -> None:
    text = path.read_text()
    if MARKER in text:
        return

    text = text.replace(
        'if carrier == "telemost" || carrier == "wbstream" || carrier == "jazz" {',
        'if carrier == "telemost" || carrier == "wbstream" {',
    )
    text, count = re.subn(
        r'\n\t\t"jazz": \{\n\t\t\t"datachannel":\s+true,\n'
        r'\t\t\t"vp8channel":\s+false,\n'
        r'\t\t\t"seichannel":\s+false,\n'
        r'\t\t\t"videochannel":\s+false,\n\t\t\},',
        "",
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit("go jazz matrix: expected one match")
    text += f"\n// {MARKER}\n"
    path.write_text(text)


def patch_tsx(path: Path) -> None:
    text = path.read_text()
    if MARKER in text:
        return

    text = replace_once(
        text,
        """type ClientLocationForm = {
  name: string;
  room_id: string;
  key: string;
  carrier: string;
  transport: string;
  payload: Record<string, string>;
  dns: string;
  link?: string;
};
""",
        """type Socks5Proxy = {
  addr: string;
  port: string;
  user: string;
  pass: string;
};

type ClientLocationForm = {
  name: string;
  room_id: string;
  jitsi_instance: string;
  key: string;
  carrier: string;
  transport: string;
  payload: Record<string, string>;
  dns: string;
  proxy: Socks5Proxy;
  link?: string;
};
""",
        "location form type",
    )
    text = replace_once(
        text,
        'const carriers = ["jitsi", "wbstream", "telemost", "jazz"];\n'
        'const transportsByCarrier: Record<string, string[]> = {\n'
        '  jitsi: ["datachannel", "vp8channel", "seichannel"],\n'
        '  wbstream: ["datachannel", "vp8channel", "seichannel"],\n'
        '  telemost: ["vp8channel", "seichannel"],\n'
        '  jazz: ["datachannel"],\n'
        '};',
        'const DEFAULT_JITSI_INSTANCE = "https://meet.handyweb.org";\n\n'
        'const carriers = ["jitsi", "wbstream", "telemost"];\n'
        'const transportsByCarrier: Record<string, string[]> = {\n'
        '  jitsi: ["datachannel", "vp8channel", "seichannel"],\n'
        '  // Keep datachannel visible: OlcRTC still implements it, but ordinary WB guest tokens\n'
        '  // currently carry canPublishData=false, so the mode is experimental.\n'
        '  wbstream: ["datachannel", "vp8channel", "seichannel"],\n'
        '  telemost: ["vp8channel", "seichannel"],\n'
        '};',
        "carrier matrix",
    )
    text = replace_once(
        text,
        '  room_id: "",\n  key: "",',
        '  room_id: "",\n  jitsi_instance: DEFAULT_JITSI_INSTANCE,\n  key: "",',
        "default jitsi instance",
    )
    text = replace_once(
        text,
        '  dns: "1.1.1.1:53",\n  link: "tor",',
        '  dns: "1.1.1.1:53",\n  proxy: { addr: "", port: "", user: "", pass: "" },\n  link: "tor",',
        "default proxy",
    )

    helpers = r'''
function splitJitsiRoomInput(value: string): { server: string; room: string } | null {
  const raw = value.trim().replace(/\/+$/, "");
  if (!raw || !raw.includes("/")) return null;
  const hasScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
  const protocolRelative = raw.startsWith("//");
  const candidate = hasScheme ? raw : protocolRelative ? `https:${raw}` : `https://${raw}`;
  try {
    const parsed = new URL(candidate);
    const parts = parsed.pathname.split("/").filter(Boolean);
    if (!parsed.host || parts.length === 0) return null;
    const room = decodeURIComponent(parts.pop() || "").trim();
    if (!room) return null;
    const suffix = parts.length ? `/${parts.join("/")}` : "";
    const server = hasScheme
      ? `${parsed.protocol}//${parsed.host}${suffix}`
      : protocolRelative
        ? `//${parsed.host}${suffix}`
        : `${parsed.host}${suffix}`;
    return { server, room };
  } catch {
    return null;
  }
}

function normalizeJitsiServer(value: string): string {
  const server = value.trim().replace(/\/+$/, "");
  if (!server) return DEFAULT_JITSI_INSTANCE;
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(server)) return server;
  if (server.startsWith("//")) return `https:${server}`;
  return `https://${server}`;
}

function combineJitsiRoomId(server: string, room: string): string {
  const base = normalizeJitsiServer(server);
  const cleanRoom = room.trim().replace(/^\/+/, "");
  return cleanRoom ? `${base}/${cleanRoom}` : base;
}

function jitsiRoomForSubmit(location: Pick<ClientLocationForm, "jitsi_instance" | "room_id">): string {
  return combineJitsiRoomId(location.jitsi_instance, location.room_id);
}

function randomRoomUUID(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = new Uint8Array(16);
  if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") crypto.getRandomValues(bytes);
  else for (let i = 0; i < bytes.length; i += 1) bytes[i] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function proxyFromState(proxy?: Partial<Socks5Proxy> & { port?: string | number }): Socks5Proxy {
  return {
    addr: proxy?.addr ?? "",
    port: proxy?.port ? String(proxy.port) : "",
    user: proxy?.user ?? "",
    pass: proxy?.pass ?? "",
  };
}

function proxyForSubmit(proxy: Socks5Proxy) {
  const addr = proxy.addr.trim();
  const port = Number(proxy.port) || 0;
  const user = proxy.user.trim();
  const pass = proxy.pass;
  if (!addr && !port && !user && !pass) return undefined;
  return { addr, port, user, pass };
}

'''
    text = replace_once(text, "function transportOptions(", helpers + "function transportOptions(", "helpers")
    text = text.replace(
        'if (c === "telemost" || c === "wbstream" || c === "jazz") {',
        'if (c === "telemost" || c === "wbstream") {',
    )
    text = replace_once(
        text,
        """function assertLocationsValid(locations: ClientLocationForm[]) {
  for (const loc of locations) {
    const err = validateRoomIDInput(loc.room_id, loc.carrier);
    if (err) throw new Error(err);
  }
}
""",
        """function assertLocationsValid(locations: ClientLocationForm[]) {
  for (const loc of locations) {
    const roomID = loc.carrier === "jitsi" ? jitsiRoomForSubmit(loc) : loc.room_id;
    const err = validateRoomIDInput(roomID, loc.carrier);
    if (err) throw new Error(err);
  }
}
""",
        "location validation",
    )

    room_component = r'''function RoomIDInput({
  value,
  carrier,
  jitsiServer,
  onChange,
  inputClassName = "h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary",
}: {
  value: string;
  carrier: string;
  jitsiServer?: string;
  onChange: (value: string) => void;
  inputClassName?: string;
}) {
  const valueForValidation = carrier === "jitsi" ? combineJitsiRoomId(jitsiServer || DEFAULT_JITSI_INSTANCE, value) : value;
  const err = value.trim() ? validateRoomIDInput(valueForValidation, carrier) : null;
  return (
    <div className="grid gap-1">
      <div className="flex gap-2">
        <input
          className={`${inputClassName} flex-1${err ? " border-destructive/70 focus:border-destructive" : ""}`}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={carrier === "jitsi" ? "room-name или полная Jitsi-ссылка" : roomPlaceholder(carrier)}
        />
        {carrier === "jitsi" ? (
          <button
            className="inline-flex h-10 items-center rounded-md border border-primary bg-secondary px-3 text-xs font-medium text-primary hover:bg-primary/10"
            type="button"
            onClick={() => onChange(randomRoomUUID())}
          >
            UUID
          </button>
        ) : null}
      </div>
      {err ? <p className="text-xs text-destructive">{err}</p> : null}
    </div>
  );
}

function Socks5ProxyFields({
  proxy,
  onChange,
  inputClassName = "h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary",
}: {
  proxy: Socks5Proxy;
  onChange: (proxy: Socks5Proxy) => void;
  inputClassName?: string;
}) {
  const set = (patch: Partial<Socks5Proxy>) => onChange({ ...proxy, ...patch });
  return (
    <div className="grid gap-3 rounded-md border border-border bg-background p-3">
      <div>
        <div className="text-sm font-medium text-foreground">Upstream SOCKS5 для этого инстанса</div>
        <p className="text-[11px] text-muted-foreground">Необязательно. Логин и пароль передаются исходящему SOCKS5-прокси OlcRTC.</p>
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        <label className="grid gap-2 text-sm text-muted-foreground">Host
          <input className={inputClassName} value={proxy.addr} onChange={(event) => set({ addr: event.target.value })} placeholder="127.0.0.1" />
        </label>
        <label className="grid gap-2 text-sm text-muted-foreground">Port
          <input className={inputClassName} type="number" min="1" max="65535" value={proxy.port} onChange={(event) => set({ port: event.target.value })} placeholder="1080" />
        </label>
        <label className="grid gap-2 text-sm text-muted-foreground">User
          <input className={inputClassName} value={proxy.user} onChange={(event) => set({ user: event.target.value })} autoComplete="off" />
        </label>
        <label className="grid gap-2 text-sm text-muted-foreground">Password
          <input className={inputClassName} type="password" value={proxy.pass} onChange={(event) => set({ pass: event.target.value })} autoComplete="new-password" />
        </label>
      </div>
    </div>
  );
}
'''
    text, count = re.subn(
        r'function RoomIDInput\(\{.*?\n\}\n\n(?=type JitsiPreflightResult)',
        room_component + "\n",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise SystemExit("RoomIDInput component: expected one match")

    normalizer = r'''function normalizeLocationForm(location: ClientLocationForm): ClientLocationForm {
  const normalized: ClientLocationForm = { ...location, proxy: proxyFromState(location.proxy) };
  if (normalized.carrier === "jitsi") {
    const fromServer = splitJitsiRoomInput(normalized.jitsi_instance || "");
    const fromRoom = splitJitsiRoomInput(normalized.room_id || "");
    const split = fromRoom || fromServer;
    if (split) {
      normalized.jitsi_instance = split.server;
      normalized.room_id = split.room;
    } else if (!normalized.jitsi_instance?.trim()) {
      normalized.jitsi_instance = DEFAULT_JITSI_INSTANCE;
    }
  }
  const options = transportOptions(normalized.carrier, normalized.transport);
  const transport = options.includes(normalized.transport) ? normalized.transport : options[0];
  const fields = payloadFields[transport] ?? [];
  const allowed = new Set(fields.map((field) => field.key));
  const payload = Object.fromEntries(Object.entries(normalized.payload).filter(([key]) => allowed.has(key)));
  for (const field of fields) {
    if (!payload[field.key]?.trim()) payload[field.key] = field.defaultValue;
  }
  const link = (normalized.link?.trim() || "tor").toLowerCase();
  return mergeInstanceDefaults({
    ...normalized,
    transport,
    payload,
    link: link === "direct" ? "direct" : "tor",
  });
}
'''
    text, count = re.subn(
        r'function normalizeLocationForm\(location: ClientLocationForm\): ClientLocationForm \{.*?\n\}\n\n(?=function normalizeForm)',
        normalizer + "\n",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise SystemExit("normalizeLocationForm: expected one match")

    submitter = r'''function locationsForSubmit(locations: ClientLocationForm[]) {
  return locations.map((location) => ({
    name: location.name.trim(),
    room_id: location.carrier === "jitsi" ? jitsiRoomForSubmit(location) : normalizeRoomIDInput(location.room_id),
    key: location.key.trim(),
    carrier: location.carrier,
    transport: location.transport,
    payload: payloadForSubmit(location.payload),
    dns: location.dns.trim(),
    proxy: proxyForSubmit(location.proxy),
    link: (location.link?.trim() || "tor").toLowerCase(),
  }));
}
'''
    text, count = re.subn(
        r'function locationsForSubmit\(locations: ClientLocationForm\[\]\) \{.*?\n\}\n\n(?=function quotaText)',
        submitter + "\n",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise SystemExit("locationsForSubmit: expected one match")

    first_server = '''      {location.carrier === "jitsi" ? (
        <label className="grid gap-2 text-sm text-muted-foreground">
          Jitsi Server
          <input
            className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            value={location.jitsi_instance}
            onChange={(event) => set({ jitsi_instance: event.target.value })}
            placeholder={DEFAULT_JITSI_INSTANCE}
          />
          <p className="text-[11px] text-muted-foreground">Можно вставить полную ссылку сюда или в Room ID — поля разделятся автоматически.</p>
        </label>
      ) : null}
'''
    second_server = '''            {location.carrier === "jitsi" ? (
              <label className="grid gap-2 text-sm text-muted-foreground">
                Jitsi Server
                <input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={location.jitsi_instance}
                  onChange={(event) => setLocation(index, { jitsi_instance: event.target.value })}
                  placeholder={DEFAULT_JITSI_INSTANCE}
                />
                <p className="text-[11px] text-muted-foreground">Полную ссылку можно вставить в любое из двух полей.</p>
              </label>
            ) : null}
'''
    text = replace_once(
        text,
        '      <label className="grid gap-2 text-sm text-muted-foreground">\n        Room ID\n',
        first_server + '      <label className="grid gap-2 text-sm text-muted-foreground">\n        Room ID\n',
        "first Jitsi server field",
    )
    text = replace_once(
        text,
        '            <label className="grid gap-2 text-sm text-muted-foreground">\n              Room ID\n',
        second_server + '            <label className="grid gap-2 text-sm text-muted-foreground">\n              Room ID\n',
        "second Jitsi server field",
    )
    text = text.replace(
        '          carrier={location.carrier}\n          onChange={(room_id)',
        '          carrier={location.carrier}\n          jitsiServer={location.jitsi_instance}\n          onChange={(room_id)',
        1,
    )
    text = text.replace(
        '                carrier={location.carrier}\n                onChange={(room_id)',
        '                carrier={location.carrier}\n                jitsiServer={location.jitsi_instance}\n                onChange={(room_id)',
        1,
    )
    text = text.replace('roomID={location.room_id}', 'roomID={location.carrier === "jitsi" ? jitsiRoomForSubmit(location) : location.room_id}')
    text = text.replace(
        '? "Jitsi: полная ссылка meet (https://…) или домен/путь"',
        '? "Jitsi: Server и Room ID сохраняются раздельно; в OlcRTC уходит одна корректная ссылка"',
    )
    text = text.replace(
        ': "Telemost / WB Stream / Jazz: только ID комнаты (цифры и латиница), без https://"',
        ': "Telemost / WB Stream: только ID комнаты (цифры и латиница), без https://"',
    )
    text = text.replace('                      <option value="jazz">jazz</option>\n', "")

    first_proxy_anchor = '''          placeholder="1.1.1.1:53"
        />
      </label>
      {fields.length > 0 && ('''
    first_proxy_replacement = '''          placeholder="1.1.1.1:53"
        />
      </label>
      <Socks5ProxyFields proxy={location.proxy} onChange={(proxy) => set({ proxy })} />
      {location.carrier === "wbstream" && location.transport === "datachannel" ? (
        <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-200">Экспериментально: OlcRTC поддерживает этот режим, но обычный WB guest-токен сейчас выдаётся с canPublishData=false. Оставлено для будущих токенов с нужными правами.</p>
      ) : null}
      {fields.length > 0 && ('''
    text = replace_once(text, first_proxy_anchor, first_proxy_replacement, "first proxy fields")

    second_proxy_anchor = '''                placeholder="1.1.1.1:53"
              />
            </label>
            {fields.length > 0 && ('''
    second_proxy_replacement = '''                placeholder="1.1.1.1:53"
              />
            </label>
            <Socks5ProxyFields
              proxy={location.proxy}
              onChange={(proxy) => setLocation(index, { proxy })}
              inputClassName="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            />
            {location.carrier === "wbstream" && location.transport === "datachannel" ? (
              <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-200">Экспериментально: core сохраняет поддержку, но guest-токен WB пока не разрешает публикацию DataChannel.</p>
            ) : null}
            {fields.length > 0 && ('''
    text = replace_once(text, second_proxy_anchor, second_proxy_replacement, "second proxy fields")

    text += f"\n// {MARKER}\n"
    path.write_text(text)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} MAIN_GO MAIN_TSX")
    go_path = Path(sys.argv[1])
    tsx_path = Path(sys.argv[2])
    patch_go(go_path)
    patch_tsx(tsx_path)
    print(f"[manager-upstream-followup] ok: {go_path} {tsx_path}")


if __name__ == "__main__":
    main()
