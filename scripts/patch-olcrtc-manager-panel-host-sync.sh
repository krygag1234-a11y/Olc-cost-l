#!/usr/bin/env bash
# After add/delete location — sync carrier hostname into direct routing lists.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'syncPanelCarrierHost' "$MAIN_GO" && { echo "[patch-panel-host-sync] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

helper = """
func panelHostSyncScript() string {
\tfor _, c := range []string{
\t\t\"/opt/Olc-cost-l/scripts/olc-sync-panel-host.sh\",
\t\t\"/usr/local/bin/olc-sync-panel-host\",
\t} {
\t\tif info, err := os.Stat(c); err == nil && !info.IsDir() {
\t\t\treturn c
\t\t}
\t}
\treturn \"\"
}

func syncPanelCarrierHost(action, carrier, roomID string) {
\tscript := panelHostSyncScript()
\tif script == \"\" {
\t\treturn
\t}
\tcarrier = strings.TrimSpace(carrier)
\troomID = strings.TrimSpace(roomID)
\tif carrier == \"\" || roomID == \"\" {
\t\treturn
\t}
\tcmd := exec.Command(\"bash\", script, action, carrier, roomID)
\tcmd.Env = append(os.Environ(), \"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\")
\tif out, err := cmd.CombinedOutput(); err != nil {
\t\tlog.Printf(\"panel host sync %s %s: %v (%s)\", action, roomID, err, strings.TrimSpace(string(out)))
\t}
}

"""

anchor = "func addLocationFromRequest"
if anchor not in t:
    raise SystemExit("[patch-panel-host-sync] addLocationFromRequest not found")
if "func syncPanelCarrierHost" not in t:
    t = t.replace(anchor, helper + anchor, 1)

# addLocation: after save, sync each new loc
old_add = """\t\t\treturn saveConfig(configPath, cfg)
\t\t}
\t}
\treturn fmt.Errorf(\"client %q not found\", clientID)
}

func deleteLocation(configPath, clientID, roomID string) error {"""

new_add = """\t\t\tfor _, loc := range locs {
\t\t\t\tsyncPanelCarrierHost(\"add\", loc.Carrier, loc.Endpoint.RoomID)
\t\t\t}
\t\t\treturn saveConfig(configPath, cfg)
\t\t}
\t}
\treturn fmt.Errorf(\"client %q not found\", clientID)
}

func deleteLocation(configPath, clientID, roomID string) error {"""

if old_add not in t:
    raise SystemExit("[patch-panel-host-sync] addLocation block not found")
t = t.replace(old_add, new_add, 1)

old_del = """\t\tif !deleted {
\t\t\treturn fmt.Errorf(\"location %q not found\", roomID)
\t\t}
\t\tcfg.Clients[i].Locations = next"""

new_del = """\t\tif !deleted {
\t\t\treturn fmt.Errorf(\"location %q not found\", roomID)
\t\t}
\t\tfor _, loc := range cfg.Clients[i].Locations {
\t\t\tif loc.Endpoint.RoomID == roomID {
\t\t\t\tsyncPanelCarrierHost(\"remove\", loc.Carrier, loc.Endpoint.RoomID)
\t\t\t\tbreak
\t\t\t}
\t\t}
\t\tcfg.Clients[i].Locations = next"""

if old_del not in t:
    raise SystemExit("[patch-panel-host-sync] deleteLocation block not found")
t = t.replace(old_del, new_del, 1)

old_client = """\tcfg.Clients = append(cfg.Clients, Client{ClientID: req.ClientID, Refresh: req.Refresh, Quota: req.Quota, Locations: locations})
\tif err := saveConfig(configPath, cfg); err != nil {
\t\treturn \"\", err
\t}
\treturn req.ClientID, nil
}"""

new_client = """\tcfg.Clients = append(cfg.Clients, Client{ClientID: req.ClientID, Refresh: req.Refresh, Quota: req.Quota, Locations: locations})
\tfor _, loc := range locations {
\t\tsyncPanelCarrierHost(\"add\", loc.Carrier, loc.Endpoint.RoomID)
\t}
\tif err := saveConfig(configPath, cfg); err != nil {
\t\treturn \"\", err
\t}
\treturn req.ClientID, nil
}"""

if old_client in t:
    t = t.replace(old_client, new_client, 1)

p.write_text(t)
print("[patch-panel-host-sync] ok")
PY
