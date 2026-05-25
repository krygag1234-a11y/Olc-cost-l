# Community zapret exclude lists (bundled)

Sources (synced by `scripts/fetch-zapret-community-excludes.sh`):

| File | Upstream |
|------|----------|
| `flowseal-list-exclude.txt` | [Flowseal list-exclude.txt](https://github.com/Flowseal/zapret-discord-youtube/blob/main/lists/list-exclude.txt) |
| `flowseal-ipset-exclude.txt` | [Flowseal ipset-exclude.txt](https://github.com/Flowseal/zapret-discord-youtube/blob/main/lists/ipset-exclude.txt) |

Merged into `zapret-sync-excludes.sh` **after** subtracting `ru-blocked-tor` (RF-blocked sites keep zapret DPI).

See also: [Flowseal #7085](https://github.com/Flowseal/zapret-discord-youtube/issues/7085), [bol-van/zapret discussions](https://github.com/bol-van/zapret/discussions).
