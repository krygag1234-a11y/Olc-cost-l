# Upstream: openlibrecommunity/olcrtc

Public reference for [olcrtc](https://github.com/openlibrecommunity/olcrtc) integration in Olc-cost-l. No deployment secrets.

## What upstream provides

| Piece | Role |
|-------|------|
| `cmd/olcrtc` | CLI client (Olcbox uses this) |
| `internal/server` | Server mode: smux tunnel + SOCKS-like dial |
| `internal/auth/*` | Carriers: **jitsi**, **wbstream**, **telemost** |
| `internal/engine/jitsi` | Jitsi Meet + colibri-ws / SCTP |
| `internal/engine/goolom` | WB Stream + Telemost (SFU WebRTC) |
| `internal/transport/*` | datachannel, **vp8channel**, seichannel, videochannel |

## Recommended carriers (upstream docs)

| Carrier | Transport | Status in upstream |
|---------|-----------|-------------------|
| **jitsi** | **datachannel** | Stable, recommended |
| jitsi | vp8channel | Marked unstable in e2e |
| **wbstream** | **vp8channel** | Stable; **datachannel does not work** |
| **telemost** | **vp8channel** | e2e expects pass; datachannel fails |
| wbstream / telemost | datachannel | Guest flow broken (`canPublishData=false`) |

See upstream [manual.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/manual.md), [settings.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/settings.md).

## Recent upstream fixes (2026-05-24 — 2026-05-25)

| Commit | Topic |
|--------|--------|
| `fe85457` | Jitsi **RTCP keepalive** (JVB session expiry) |
| `c2170c0` | Jitsi **SCTP fallback** when colibri-ws unavailable |
| `83a9494` | **vp8channel**: latch peer epoch on first frame |
| `6d529c1` | vp8channel: latch only after handshake confirms peer |
| `cefd260` | vp8channel: multiple simultaneous clients |

**Olc-cost-l pin target:** `af9eeea` (includes above + docs).

## What Olc-cost-l adds (still required)

Upstream has **no** Tor split, **no** RU CIDR lists, **no** zapret. We ship:

- `internal/routing/*` — direct vs Tor by domain/CIDR
- `patch-olcrtc-core.sh` — SOCKS + split in server
- `patch-olcrtc-server-jitsi-no-smux-reconnect.sh` — do not kill VPN smux on Jitsi bridge flap
- `patch-olcrtc-server-reconnect-debounce.sh` — 5s debounce for WB/Telemost
- `patch-olcrtc-goolom-reconnect-stable.sh` — softer goolom reconnect queue
- Jitsi datachannel MTU `16*1024-12`

## WB / Telemost troubleshooting

1. Panel must use **`vp8channel`**, not datachannel.
2. Update olcrtc to pin with **vp8 fixes** (`83a9494+`).
3. Ensure zapret excludes: `stream.wb.ru`, `cloud-api.yandex.ru`, `telemost.yandex.ru`, `*.livekit.cloud` (see `data/zapret-carrier-hosts.txt`).
4. Client: one room per connect; wait for `VPN tunnel established` before browsing.

## Jitsi troubleshooting

1. Zapret must bypass `meet.cryptopro.ru` in **netrogat** and **nozapret** ipset.
2. Do not reinstall smux on Jitsi carrier reconnect (our patch) — otherwise Olcbox sees `control: read hdr: EOF`.
3. Use **one** subscription room at a time if client opens multiple Jitsi URLs.

## Update procedure

```bash
# After changing data/upstream-pins.json:
sudo UPSTREAM_FRESH=0 bash /opt/Olc-cost-l/scripts/apply-olcrtc-patches.sh
sudo systemctl restart olcrtc-manager
```

Or: `sudo bash /opt/Olc-cost-l/install.sh --update`
