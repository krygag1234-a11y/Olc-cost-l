# zapret4rocket (optional full DPI config)

Upstream: https://github.com/IndeecFOX/zapret4rocket

```bash
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --apply
# refresh /opt/zapret/config from upstream (backup first):
sudo /opt/Olc-cost-l/scripts/sync-zapret4rocket.sh --apply --config
```

Without `config.default`, `install-zapret-vps.sh` uses minimal `data/zapret-olcrtc.config`.

Override:

```bash
export Z4R_SRC=/path/to/zapret4rocket
export Z4R_REPO_URL=https://github.com/IndeecFOX/zapret4rocket.git
```
