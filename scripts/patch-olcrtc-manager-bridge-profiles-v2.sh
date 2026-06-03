#!/usr/bin/env bash
# Bridge profiles v2: apply active profile to bridges pool/bridges.conf flow.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'func applyActiveBridgeProfile' "$MAIN_GO" && { echo "[patch-bridge-profiles-v2] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if '"io"' not in t.split("import (", 1)[1].split(")", 1)[0]:
    t = t.replace("import (\n", "import (\n\t\"io\"\n", 1)

helpers = r'''
func profileBridgeLinesFromBody(profile map[string]any) []string {
	out := []string{}
	if b, ok := profile["bridges"].(string); ok {
		for _, line := range strings.Split(b, "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if !strings.HasPrefix(line, "Bridge ") {
				line = "Bridge " + line
			}
			out = append(out, line)
		}
	}
	return out
}

func fetchProfileBridgeLines(profile map[string]any) []string {
	out := profileBridgeLinesFromBody(profile)
	urls, ok := profile["urls"].([]any)
	if !ok {
		return out
	}
	client := http.Client{Timeout: 20 * time.Second}
	for _, u := range urls {
		url, _ := u.(string)
		url = strings.TrimSpace(url)
		if url == "" {
			continue
		}
		resp, err := client.Get(url)
		if err != nil || resp.StatusCode >= 300 {
			if resp != nil {
				resp.Body.Close()
			}
			continue
		}
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024))
		resp.Body.Close()
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if !strings.HasPrefix(line, "Bridge ") {
				line = "Bridge " + line
			}
			out = append(out, line)
		}
	}
	return out
}

func applyActiveBridgeProfile(profiles map[string]any) error {
	active, _ := profiles["active_profile"].(string)
	if active == "" || active == "system" {
	sys, _ := profiles["system"].(map[string]any)
	types, _ := sys["types"].(string)
	if strings.TrimSpace(types) == "" {
		types = "obfs4"
	}
	runBridgePoolRefresh(types)
		return nil
	}
	profs, _ := profiles["profiles"].([]any)
	var selected map[string]any
	for _, p := range profs {
		m, _ := p.(map[string]any)
		if m != nil && fmt.Sprint(m["id"]) == active {
			selected = m
			break
		}
	}
	if selected == nil {
		return nil
	}
	lines := fetchProfileBridgeLines(selected)
	if len(lines) == 0 {
		return nil
	}
	userPath := "/var/lib/olcrtc/tor-user-bridges.txt"
	body := strings.Join(lines, "\n") + "\n"
	if err := writeTextFile(userPath, body); err != nil {
		return err
	}
	types, _ := selected["types"].(string)
	if strings.TrimSpace(types) == "" {
		types = "obfs4"
	}
	runBridgePoolRefresh(types)
	return nil
}

'''

if "func applyActiveBridgeProfile" not in t:
    t = t.replace(
        "func componentSettingsGet(name string) (map[string]any, error) {",
        helpers + "func componentSettingsGet(name string) (map[string]any, error) {",
        1,
    )

if "applyActiveBridgeProfile(cur)" not in t:
    t = t.replace(
        '''			if ap, ok := body["active_profile"].(string); ok {
				cur["active_profile"] = ap
			}
			return writeBridgeProfiles(cur)''',
        '''			if ap, ok := body["active_profile"].(string); ok {
				cur["active_profile"] = ap
			}
			if err := writeBridgeProfiles(cur); err != nil {
				return err
			}
			return applyActiveBridgeProfile(cur)''',
        1,
    )

p.write_text(t)
print("[patch-bridge-profiles-v2] ok")
PY
