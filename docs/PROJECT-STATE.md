# PROJECT-STATE — Olc-cost-l + production VPS

**Generated:** 2026-05-25  
**Purpose:** Single reference for agents/operators: what the repo does, what runs on VPS, upstream deltas, and verification status.

---

## 1. Olc-cost-l repository (our stack)

### 1.1 Role

[Olc-cost-l](https://github.com/krygag1234-a11y/Olc-cost-l) is **not** a fork of olcrtc. It is an **integration layer**:

| Layer | Upstream | Our addition |
|-------|----------|--------------|
| Core tunnel | [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) `master` | Idempotent `patch-olcrtc-*.sh`, routing CIDR/domains, Jitsi 16K payload, reconnect debounce |
| Panel | [BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel) `main` | SOCKS split env, liveness tuning, logs API query fix, `exitProxyReachable` |
| DPI egress | [bol-van/zapret](https://github.com/bol-van/zapret) + [zapret4rocket](https://github.com/IndeecFOX/zapret4rocket) | `install-zapret-vps.sh`, **`zapret-sync-excludes.sh`** |
| Client | [olcbox nightly](https://github.com/alananisimov/olcbox/releases/tag/nightly) | Documented in `docs/CLIENT.md` |

**Design goals (preserved):**

- `install.sh` / `agent-bootstrap.sh` flags: `--full`, `--update`, `--no-tor`, `--no-split`, `--foreign`
- `safety-lib.sh` path allowlists — no destructive writes outside `/var/lib/olcrtc`, `/etc/olcrtc-manager`, `/opt/zapret`
- Tor bridge pool: obfs4-first when IPv4 webtunnel missing (`OLCRTC_BRIDGE_IPV4_ONLY=1`)
- Split: `*.ru` + geosite direct; `ru-blocked-tor` → direct + **zapret**; `force-tor` → Tor only

### 1.2 Key scripts (deployed to `/opt/Olc-cost-l`)

| Script | Function |
|--------|----------|
| `install.sh` | Entry: clone/update repo, `agent-bootstrap` |
| `agent-bootstrap.sh` | Patches, Tor, split lists, zapret sync, systemd, cron |
| `apply-olcrtc-patches.sh` | Clone upstream at pin → patch → `go build` |
| `setup-split-ru.sh` | geoip RU + geosite domains + panel.env |
| **`zapret-sync-excludes.sh`** | Merge direct RU − blocked → `netrogat.txt` + `nozapret` ipset |
| `fetch-zapret-community-excludes.sh` | Pull [Flowseal list-exclude](https://github.com/Flowseal/zapret-discord-youtube/blob/main/lists/list-exclude.txt) |
| `sync-zapret-hostlist.sh` | RF-blocked only → `zapret-hosts-user.txt` |
| `healthcheck.sh` | Tor TCP check only (no false bridge rotation) |
| `smoke-test.sh` | Post-deploy syntax + zapret-sync sanity |
| `upstream-sync.sh` | Check/apply upstream SHAs from `data/upstream-pins.json` |

### 1.3 Zapret exclusion model (critical)

Two bypass mechanisms on VPS:

1. **`/opt/zapret/lists/netrogat.txt`** — nfqws hostlist: first rule passes matching domains without DPI.
2. **`ipset nozapret`** — iptables: dst IP in set **never enters NFQUEUE**.

**Sources merged into netrogat** (~17k lines):

- `ru-direct-domains.txt` (geosite RU)
- `data/zapret-carrier-hosts.txt`, `zapret-netrogat-extra.txt`
- `data/zapret-community-excludes/flowseal-list-exclude.txt`
- Minus `ru-blocked-tor-domains.txt` + `force-tor-domains.txt`

**Carrier IPs** (meet.cryptopro.ru `/24`, WB, Yandex) injected into `nozapret` after DNS resolve — fixes Jitsi XMPP `EOF` when domain list alone was insufficient.

**Community references applied:**

- [Flowseal ipset-exclude](https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/lists/ipset-exclude.txt) — private LAN CIDRs
- [Flowseal list-exclude](https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/lists/list-exclude.txt) — VK, WB, banks, Yandex, etc.
- [Issue #7085](https://github.com/Flowseal/zapret-discord-youtube/issues/7085) — community RU whitelist patterns
- zapret4rocket changelog: exclusions also apply to UDP; carrier IP in ipset mandatory for WebSocket

### 1.4 Pins (`data/upstream-pins.json`)

| Component | Pinned SHA | Upstream head (2026-05-25) |
|-----------|------------|----------------------------|
| olcrtc | `933fb158…` | same — Jitsi RTCP keepalive, SCTP fallback |
| manager | `ad8ec6f6…` | same — subscription refresh |
| zapret4rocket | `bf8eafef…` | same — recommendations updates |

**Not verified on test VPS after pin bump** — run `upstream-sync.sh --apply` on staging first.

### 1.5 Verification status (scripts)

| Item | Status |
|------|--------|
| `smoke-test.sh` on prod VPS | ✅ passed (with 120s zapret-sync timeout) |
| `install.sh` curl pipe | ⚠️ not re-run end-to-end this session |
| Test VPS `111.88.149.45` | 🔄 smoke + syntax (see §4) |

**Label:** Scripts below were brought to successful deploy on **production** `89.169.185.216`; not every path re-tested on clean test VPS in this session.

---

## 2. Production VPS state (89.169.185.216)

### 2.1 Services (expected)

```
systemctl is-active tor@default olcrtc-manager  → active
pidof nfqws                                      → running
panel :8888 /admin                               → HTTP 200
```

### 2.2 Layout

| Path | Content |
|------|---------|
| `/opt/Olc-cost-l` | Git clone of Olc-cost-l |
| `/usr/local/bin/olcrtc`, `olcrtc-manager` | Patched binaries |
| `/etc/olcrtc-manager/panel.env` | Split paths, `OLCRTC_PUBLIC_URL` |
| `/var/lib/olcrtc/` | `ru-cidrs.txt`, `ru-direct-domains.txt`, `ru-blocked-tor-domains.txt`, manager-run YAML |
| `/opt/zapret/` | zapret4rocket full config, nfqws |
| `/opt/zapret/lists/netrogat.txt` | ~17301 lines after sync |
| `/var/log/olcrtc-healthcheck.log` | Tor rotate only when 9050 down |

### 2.3 Manager instances (typical)

3 clients × Jitsi datachannel → `meet.cryptopro.ru` rooms (ShopSmoothly, Shop, Exams). Each `link: tor` with SOCKS `127.0.0.1:9050` + split files.

**Known good log line:**

```
jitsi: joined meet.cryptopro.ru/…; colibri-ws=wss://…
Link connected
session opened
```

### 2.4 Issues fixed (2026-05-24 — 2026-05-25)

| Symptom | Cause | Fix |
|---------|-------|-----|
| Jitsi XMPP EOF | zapret DPI on `193.37.157.0/24` without ipset bypass | `nozapret` + netrogat |
| VK slow / timeout | netrogat had ~35 lines | full `zapret-sync-excludes` |
| Intermittent Tor flap | healthcheck `check.torproject.org` false negative | `OLCRTC_TOR_DEEP_CHECK=0` default |
| Olcbox “offline” but connects | control pong + zapret flaps + multi-room churn | above + user: one room, don’t Stop VPN during join |

---

## 3. Upstream: openlibrecommunity/olcrtc

**Repo:** https://github.com/openlibrecommunity/olcrtc  
**License:** WTFPL · **Stars:** ~1.3k · **Language:** Go 90%

### 3.1 Architecture

- **Modes:** `cli` (Olcbox) / `srv` (manager-spawned)
- **Carriers:** `jitsi`, `wbstream`, `telemost` — auth in `internal/auth/*`
- **Transports:** `datachannel` (Jitsi), `vp8channel`, `seichannel`, `videochannel`
- **Tunnel:** smux over KCP/datachannel; SOCKS5 on client `127.0.0.1:10808`
- **Routing (upstream):** minimal; **our patches** add `direct_cidrs_file`, `direct_domains_file`, `blocked_tor_domains_file`

### 3.2 Recent upstream commits (not just latest)

| Date | SHA | Summary |
|------|-----|---------|
| 2026-05-25 | 933fb158 | docs whitelist notice |
| 2026-05-25 | fe854577 | **fix(jitsi): RTCP keepalive** — JVB session expiry |
| 2026-05-25 | c2170c05 | **feat(jitsi): SCTP fallback** when colibri-ws unavailable |
| 2026-05-25 | e64ed167 | refactor openBridgeWS / openBridgeSCTP |

### 3.3 Gap vs Olc-cost-l

We still **require patches** for: 16K−12 datachannel MTU, split routing files, server reconnect debounce, goolom carrier debounce. Upstream merge of routing is partial — keep `patch-olcrtc-core.sh` until upstream absorbs.

**Action:** Pin bumped to `933fb158`; run `apply-olcrtc-patches.sh` and regression-test Jitsi/WB/Telemost.

---

## 4. Upstream: BigDaddy3334/olcrtc-manager-panel

**Repo:** https://github.com/BigDaddy3334/olcrtc-manager-panel  
**Stack:** Go + embedded React (`web/dist`)

### 4.1 Role

- Subscriptions for Olcbox (base64 YAML locations)
- Spawns `olcrtc` per location with generated YAML in `/var/lib/olcrtc/manager-run/`
- Quota, logs API, admin UI `:8888`

### 4.2 Recent commits

| Date | SHA | Summary |
|------|-----|---------|
| 2026-05-24 | ad8ec6f6 | Merge PR #28 subscription refresh settings |
| 2026-05-22 | 6878fc83 | Installer uses olcrtc master |
| 2026-05-18 | 27ffc374 | Server memory metric in panel |

### 4.3 Gap vs Olc-cost-l

Our patches add: `OLCRTC_DIRECT_*` env → server YAML SOCKS block, `exitProxyReachable`, relaxed liveness for datachannel, Jitsi room URL helper, logs via query params.

**Action:** Pin `ad8ec6f6`; verify subscription refresh does not conflict with patched `main.go`.

---

## 5. Upstream: IndeecFOX/zapret4rocket

**Repo:** https://github.com/IndeecFOX/zapret4rocket) · proxy menu: [z4r](https://github.com/IndeecFOX/z4r)

### 5.1 Role

- Ships `config.default` for nfqws (RKN multidisorder, YouTube, Discord UDP, user lists)
- `netrogat.txt` placeholder + menu to add `ru` TLD exclusions
- **Olc-cost-l** replaces manual exclusions with **`zapret-sync-excludes.sh`**

### 5.2 Recent commits

Daily `Update recommendations` (May 18–25); config strategy churn for RKN wave.

### 5.3 Integration

- `sync-zapret4rocket.sh` clones to `data/zapret4rocket/` (gitignored except README)
- `OLCRTC_ZAPRET_FULL=1` on VPS ≥4GB RAM → full config.default
- `OLCRTC_ZAPRET_REINSTALL=0` on `--update` → only `zapret-sync-excludes.sh --reload-zapret`

---

## 6. Comparison matrix: adopt from community

| Source | Adopted in Olc-cost-l |
|--------|----------------------|
| Flowseal `list-exclude.txt` | ✅ `data/zapret-community-excludes/` + sync |
| Flowseal `ipset-exclude.txt` | ✅ private CIDRs in hosts-user-exclude |
| zapret4rocket netrogat menu | ✅ superseded by automated sync |
| Flowseal #3290 huge IP lists | ❌ too broad; we use geosite RU + subtract blocked |
| bol-van discussions 1532/858 | 📖 DPI/WebSocket semantics — ipset bypass |
| ChickenVDS | ❌ unrelated (VDS bot) |

---

## 7. Test VPS checklist

```bash
ssh -i /root/.ssh/yandex_bm_test_key kryga@111.88.149.45
sudo bash /opt/Olc-cost-l/scripts/smoke-test.sh
sudo bash /opt/Olc-cost-l/scripts/fetch-zapret-community-excludes.sh
# after install/update:
sudo bash /opt/Olc-cost-l/scripts/zapret-sync-excludes.sh --reload-zapret
```

---

## 8. Operator commands (quick)

```bash
# Full update on RU VPS
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --update

# Zapret exclusions only
sudo bash /opt/Olc-cost-l/scripts/zapret-sync-excludes.sh --reload-zapret

# Upstream check
sudo bash /opt/Olc-cost-l/scripts/upstream-sync.sh --check
```

---

*This file is maintained for agent continuity. Update after pin changes, VPS migrations, or major script additions.*
