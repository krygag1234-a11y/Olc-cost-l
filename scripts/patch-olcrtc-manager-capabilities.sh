#!/usr/bin/env bash
# GET /api/capabilities — installed components + panel version for conditional UI.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'capabilitiesHandler' "$MAIN_GO" && { echo "[patch-capabilities] already applied"; exit 0; }

python3 - "$MAIN_GO" "$REPO_ROOT" <<'PY'
import json
import sys
from pathlib import Path

main_go = Path(sys.argv[1])
repo = Path(sys.argv[2])
t = main_go.read_text()

route = '\thandler.Handle("/api/capabilities", adminAuth(http.HandlerFunc(capabilitiesHandler())))\n'
anchor = '\thandler.Handle("/api/features", adminAuth(http.HandlerFunc(featuresListHandler())))'
if route.strip() not in t:
    t = t.replace(anchor, route + anchor, 1)

helpers = r'''
func readVersionJSON() map[string]any {
	out := map[string]any{"panel": "0.0.0", "channel": "alpha"}
	for _, p := range []string{
		"/opt/Olc-cost-l/version.json",
		"/opt/olcrtc/version.json",
	} {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var v map[string]any
		if json.Unmarshal(b, &v) == nil {
			return v
		}
	}
	return out
}

func readDeployProfileID() string {
	for _, p := range []string{"/etc/olcrtc-manager/deploy-profile.json"} {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var v struct {
			ProfileID string `json:"profile_id"`
		}
		if json.Unmarshal(b, &v) == nil && v.ProfileID != "" {
			return v.ProfileID
		}
	}
	return ""
}

func componentInstalled(name string) bool {
	switch name {
	case "zapret":
		if _, err := os.Stat("/opt/zapret/nfq/nfqws"); err == nil {
			return true
		}
		return false
	case "tor":
		if _, err := os.Stat("/etc/tor/torrc"); err == nil {
			return true
		}
		return false
	case "split":
		if _, err := os.Stat("/var/lib/olcrtc/lists"); err == nil {
			return true
		}
		return false
	case "bridges", "webtunnel":
		if _, err := os.Stat("/usr/bin/webtunnel-client"); err == nil {
			return true
		}
		if _, err := os.Stat("/etc/tor/bridges.conf"); err == nil {
			return true
		}
		return false
	default:
		return false
	}
}

func loadFeatureFlagsMap() map[string]bool {
	flags := map[string]bool{"zapret": true, "tor": true, "split": true, "webtunnel": true}
	path := "/etc/olcrtc-manager/features.env"
	b, err := os.ReadFile(path)
	if err != nil {
		return flags
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key, val := strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])
		enabled := val == "1" || strings.EqualFold(val, "true")
		switch key {
		case "OLCRTC_ENABLE_ZAPRET":
			flags["zapret"] = enabled
		case "OLCRTC_ENABLE_TOR":
			flags["tor"] = enabled
		case "OLCRTC_ENABLE_SPLIT":
			flags["split"] = enabled
		case "OLCRTC_ENABLE_WEBTUNNEL":
			flags["webtunnel"] = enabled
		}
	}
	return flags
}

func capabilitiesHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		flags := loadFeatureFlagsMap()
		ver := readVersionJSON()
		profile := readDeployProfileID()
		type comp struct {
			Installed    bool     `json:"installed"`
			Enabled      bool     `json:"enabled"`
			Configurable bool     `json:"configurable"`
			Label        string   `json:"label,omitempty"`
			Requires     []string `json:"requires,omitempty"`
		}
		components := map[string]comp{
			"zapret": {
				Installed: componentInstalled("zapret"), Enabled: flags["zapret"],
				Configurable: componentInstalled("zapret"), Label: "Zapret",
			},
			"tor": {
				Installed: componentInstalled("tor"), Enabled: flags["tor"],
				Configurable: componentInstalled("tor"), Label: "Tor",
			},
			"split": {
				Installed: componentInstalled("split"), Enabled: flags["split"],
				Configurable: componentInstalled("split"), Label: "Split",
				Requires: []string{"tor"},
			},
			"bridges": {
				Installed: componentInstalled("bridges"), Enabled: flags["webtunnel"],
				Configurable: componentInstalled("tor"), Label: "Мосты",
			},
		}
		writeJSON(w, map[string]any{
			"panel_version":  ver["panel"],
			"channel":        ver["channel"],
			"deploy_profile": profile,
			"components":     components,
		})
	}
}

'''

if "func capabilitiesHandler" not in t:
    anchor2 = "func featuresListHandler()"
    t = t.replace(anchor2, helpers + "\n" + anchor2, 1)

main_go.write_text(t)
print("[patch-capabilities] ok")
PY
