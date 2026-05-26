#!/usr/bin/env bash
# GET/PUT /api/settings/{zapret|tor|split|bridges} — component settings for panel modals.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'componentSettingsHandler' "$MAIN_GO" && { echo "[patch-component-settings] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

route = '\thandler.Handle("/api/settings/", adminAuth(http.HandlerFunc(componentSettingsHandler())))\n'
anchor = '\thandler.Handle("/api/capabilities", adminAuth(http.HandlerFunc(capabilitiesHandler())))'
if route.strip() not in t:
    t = t.replace(anchor, route + anchor, 1)

helpers = r'''
func readTextFile(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(b)
}

func writeTextFile(path, body string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(body), 0644)
}

func torSocksPort() string {
	b := readTextFile("/etc/tor/torrc")
	for _, line := range strings.Split(b, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "SocksPort ") {
			return strings.TrimSpace(strings.TrimPrefix(line, "SocksPort"))
		}
	}
	return "9050"
}

func componentSettingsGet(name string) (map[string]any, error) {
	switch name {
	case "zapret":
		return map[string]any{
			"auto_sync":            fileExists("/etc/cron.d/olcrtc-zapret-sync") || fileExists("/etc/cron.d/zapret-sync"),
			"exclude_domains":      readTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt"),
			"force_domains":        readTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt"),
			"community_sync":       fileExists("/var/lib/olcrtc/lists"),
		}, nil
	case "tor":
		return map[string]any{
			"socks_port":           torSocksPort(),
			"exit_nodes":           grepTorrcLine("ExitNodes"),
			"exclude_exit_nodes":   grepTorrcLine("ExcludeExitNodes"),
			"bridges_enabled":      fileExists("/etc/tor/bridges.conf"),
		}, nil
	case "split":
		return map[string]any{
			"custom_direct_domains": readTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt"),
			"panel_hosts":           readTextFile("/var/lib/olcrtc/lists/panel-carrier-hosts.txt"),
			"ru_direct_count":       countLines("/var/lib/olcrtc/ru-direct-domains.txt"),
		}, nil
	case "bridges":
		return map[string]any{
			"bridges_conf": readTextFile("/etc/tor/bridges.conf"),
			"webtunnel":    fileExists("/usr/bin/webtunnel-client"),
		}, nil
	default:
		return nil, fmt.Errorf("unknown component %q", name)
	}
}

func grepTorrcLine(key string) string {
	for _, line := range strings.Split(readTextFile("/etc/tor/torrc"), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, key) {
			return strings.TrimSpace(strings.TrimPrefix(line, key))
		}
	}
	return ""
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func countLines(path string) int {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	n := 0
	for _, line := range strings.Split(string(b), "\n") {
		if strings.TrimSpace(line) != "" && !strings.HasPrefix(strings.TrimSpace(line), "#") {
			n++
		}
	}
	return n
}

func componentSettingsPut(name string, body map[string]any) error {
	switch name {
	case "zapret":
		if v, ok := body["exclude_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/exclude-domains.txt", v); err != nil {
				return err
			}
		}
		if v, ok := body["force_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/zapret-custom/force-domains.txt", v); err != nil {
				return err
			}
		}
		return nil
	case "tor":
		// Tor port / exit nodes — warn only in UI; full torrc edit needs olc-update
		return nil
	case "split":
		if v, ok := body["custom_direct_domains"].(string); ok {
			if err := writeTextFile("/var/lib/olcrtc/lists/custom-direct-domains.txt", v); err != nil {
				return err
			}
		}
		return nil
	case "bridges":
		if v, ok := body["custom_bridge"].(string); ok && strings.TrimSpace(v) != "" {
			line := strings.TrimSpace(v)
			if !strings.HasPrefix(line, "Bridge ") {
				line = "Bridge " + line
			}
			f, err := os.OpenFile("/etc/tor/bridges.conf", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
			if err != nil {
				return err
			}
			defer f.Close()
			_, err = fmt.Fprintf(f, "\n%s\n", line)
			return err
		}
		return nil
	default:
		return fmt.Errorf("unknown component %q", name)
	}
}

func componentSettingsHandler() http.HandlerFunc {
	allowed := map[string]bool{"zapret": true, "tor": true, "split": true, "bridges": true}
	return func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/api/settings/")
		name = strings.TrimSpace(strings.Trim(name, "/"))
		if !allowed[name] {
			http.Error(w, "unknown component", http.StatusBadRequest)
			return
		}
		switch r.Method {
		case http.MethodGet:
			out, err := componentSettingsGet(name)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]any{"component": name, "settings": out})
		case http.MethodPut:
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			if err := componentSettingsPut(name, body); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]string{"status": "ok"})
		default:
			w.Header().Set("Allow", "GET, PUT")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}
}

'''

if '"path/filepath"' not in t:
    t = t.replace('"path/filepath"\n', '"path/filepath"\n', 1)
if '"path/filepath"' not in t.split("import (")[1].split(")")[0]:
    t = t.replace('"os"\n', '"os"\n\t"path/filepath"\n', 1)

if "func componentSettingsHandler" not in t:
    t = t.replace("func capabilitiesHandler()", helpers + "\nfunc capabilitiesHandler()", 1)

p.write_text(t)
print("[patch-component-settings] ok")
PY
