# Data files

| File | Purpose |
|------|---------|
| `bridge-extra-urls.txt` | Extra Tor bridge list URLs (Tor-Bridges-Collector), merged on fetch |
| `ru-domains-extra.txt` | Suffix domains for direct routing (e.g. `2ipcore.com`) |
| `zapret-netrogat-extra.txt` | Static carrier hosts → zapret `netrogat.txt` |
| `zapret-carrier-hosts.txt` | WB / Telemost / Yandex / LiveKit API hosts |
| Other `*.txt` | Seeded by `setup-split-ru.sh` into `/var/lib/olcrtc/` |

**Zapret exclusions:** `scripts/zapret-sync-excludes.sh` merges direct-domain lists minus `ru-blocked-tor` into `/opt/zapret/lists/netrogat.txt`. Optional extra whitelist: `OLCRTC_ZAPRET_WHITELIST_EXTRA=/path/to/file`.
