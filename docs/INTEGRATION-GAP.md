# Integration gap: Olc-cost-l vs upstream

How our repo extends upstream projects (public overview).

## olcrtc ([openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc))

| Area | Upstream | Olc-cost-l |
|------|----------|------------|
| Egress | Single path | Tor SOCKS + **split** (RU direct, rest Tor) |
| RF-blocked .ru | N/A | Direct + **zapret** DPI |
| Jitsi carrier reconnect | Internal bridge reconnect | **No smux tear-down** (patch) |
| WB/Telemost | goolom + vp8 | Same + **reconnect debounce** + zapret excludes |
| Build pin | `master` moving | `data/upstream-pins.json` |

**Adopt from upstream regularly:** Jitsi RTCP/SCTP commits, vp8channel epoch fixes.

## olcrtc-manager-panel

| Area | Upstream | Olc-cost-l |
|------|----------|------------|
| SOCKS / split env | Partial / none | Full env files for lists |
| Default link | varies | `link: tor` default |
| Liveness | strict | Relaxed for datachannel/vp8 |
| VP8 defaults | — | 50/50 fps/batch |

## zapret4rocket

| Area | Upstream | Olc-cost-l |
|------|----------|------------|
| netrogat | Manual menu | **`zapret-sync-excludes.sh`** from split lists |
| RU whitelist | User adds | geosite RU + Flowseal community list |

## When to run what

| Goal | Command |
|------|---------|
| Refresh domain lists | `setup-split-ru.sh` |
| Refresh zapret exclusions | `zapret-sync-excludes.sh --reload-zapret` |
| Rebuild binaries | `apply-olcrtc-patches.sh` |
| Check upstream drift | `upstream-sync.sh --check` |
