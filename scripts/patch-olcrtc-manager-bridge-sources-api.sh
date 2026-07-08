#!/usr/bin/env bash
# Phase 1 (мосты) — bridge sources API + init function.
# Idempotent. Target: manager main.go.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-bridge-sources] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-bridge-sources] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-bridge-sources] {label}: ok")
    else:
        print(f"[patch-bridge-sources] WARN {label}: anchor not found (len={len(old)})")

# --- 1. Add bridge sources functions before bridgeHealthList ---
repl(
    'func bridgeHealthList() []map[string]any {',
    'const bridgeSourcesPath = "/var/lib/olcrtc/bridge-sources.json"\n\nfunc defaultBridgeSources() []map[string]any {\n\treturn []map[string]any{\n\t\t{"id": "primary", "url": "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/TOR-BRIDGES/TOR_BRIDGES_ALL.txt", "label": "vpn-configs-for-russia (primary)", "enabled": true, "editable": false},\n\t\t{"id": "dt-obfs4", "url": "https://raw.githubusercontent.com/Delta-Kronecker/Tor-Bridges-Collector/main/bridge/obfs4_tested.txt", "label": "Tor-Bridges-Collector (obfs4)", "enabled": true, "editable": false},\n\t\t{"id": "dt-wt", "url": "https://raw.githubusercontent.com/Delta-Kronecker/Tor-Bridges-Collector/main/bridge/webtunnel_tested.txt", "label": "Tor-Bridges-Collector (webtunnel)", "enabled": true, "editable": false},\n\t}\n}\n\nfunc readBridgeSources() []map[string]any {\n\tvar sources []map[string]any\n\tif readJSONFile(bridgeSourcesPath, &sources) {\n\t\treturn sources\n\t}\n\tsources = defaultBridgeSources()\n\twriteBridgeSources(sources)\n\treturn sources\n}\n\nfunc writeBridgeSources(sources []map[string]any) error {\n\tb, err := json.MarshalIndent(sources, "", "  ")\n\tif err != nil { return err }\n\tif err := os.MkdirAll(filepath.Dir(bridgeSourcesPath), 0755); err != nil { return err }\n\treturn os.WriteFile(bridgeSourcesPath, b, 0644)\n}\n\nfunc writeExtraURLSFile(sources []map[string]any) {\n\tvar lines []string\n\tfor _, s := range sources {\n\t\ten, _ := s["enabled"].(bool)\n\t\tif en {\n\t\t\tif u, _ := s["url"].(string); u != "" {\n\t\t\t\tlines = append(lines, u)\n\t\t\t}\n\t\t}\n\t}\n\tif len(lines) == 0 {\n\t\t_ = os.WriteFile("/var/lib/olcrtc/bridge-extra-urls.txt", []byte{}, 0644)\n\t\treturn\n\t}\n\t_ = os.WriteFile("/var/lib/olcrtc/bridge-extra-urls.txt", []byte(strings.Join(lines, "\\n")+"\\n"), 0644)\n}\n\nfunc initBridgeSources() {\n\tif _, err := os.Stat(bridgeSourcesPath); os.IsNotExist(err) {\n\t\twriteBridgeSources(defaultBridgeSources())\n\t} else {\n\t\textraFile := "/var/lib/olcrtc/bridge-extra-urls.txt"\n\t\tif eb, eerr := os.ReadFile(extraFile); eerr == nil {\n\t\t\texisting := readBridgeSources()\n\t\t\turls := strings.Split(strings.TrimSpace(string(eb)), "\\n")\n\t\t\tfor _, u := range urls {\n\t\t\t\tu = strings.TrimSpace(u)\n\t\t\t\tif u == "" || strings.HasPrefix(u, "#") { continue }\n\t\t\t\tfound := false\n\t\t\t\tfor _, s := range existing {\n\t\t\t\t\tif s["url"] == u { found = true; break }\n\t\t\t\t}\n\t\t\t\tif !found {\n\t\t\t\t\tlabel := strings.TrimSpace(u)\n\t\t\t\t\tif idx := strings.LastIndex(u, "/"); idx >= 0 {\n\t\t\t\t\t\tlabel = u[idx+1:]\n\t\t\t\t\t\tif dot := strings.Index(label, "."); dot > 0 { label = label[:dot] }\n\t\t\t\t\t}\n\t\t\t\t\tif len(label) > 60 { label = label[:60] }\n\t\t\t\t\texisting = append(existing, map[string]any{\n\t\t\t\t\t\t"id": "legacy-" + strconv.Itoa(len(existing)),\n\t\t\t\t\t\t"url": u, "label": label, "enabled": true, "editable": true,\n\t\t\t\t\t})\n\t\t\t\t}\n\t\t\t}\n\t\t\tif len(existing) > len(defaultBridgeSources()) {\n\t\t\t\twriteBridgeSources(existing)\n\t\t\t}\n\t\t}\n\t}\n}\n\nfunc bridgeHealthList() []map[string]any {',
    "bridge sources API + init",
    guard='func defaultBridgeSources()',
)

# --- 2. Register /api/sources/bridges route (exact match with tab) ---
repl(
    '\thandler.Handle("/api/components/", adminAuth(http.HandlerFunc(componentsActionHandler)))',
    '\thandler.Handle("/api/sources/bridges", adminAuth(http.HandlerFunc(bridgeSourcesHandler())))\n\thandler.Handle("/api/components/", adminAuth(http.HandlerFunc(componentsActionHandler)))',
    "sources route registration",
    guard='bridgeSourcesHandler',
)

# --- 3. Add bridgeSourcesHandler function ---
repl(
    'func componentSettingsAfterSave(name string, body map[string]any) {',
    'func bridgeSourcesHandler() http.HandlerFunc {\n\treturn func(w http.ResponseWriter, r *http.Request) {\n\t\tswitch r.Method {\n\t\tcase http.MethodGet:\n\t\t\tsources := readBridgeSources()\n\t\t\twriteExtraURLSFile(sources)\n\t\t\twriteJSON(w, map[string]any{"status": "ok", "sources": sources})\n\t\tcase http.MethodPut:\n\t\t\tvar body map[string]any\n\t\t\tif err := json.NewDecoder(r.Body).Decode(&body); err != nil {\n\t\t\t\thttp.Error(w, err.Error(), http.StatusBadRequest)\n\t\t\t\treturn\n\t\t\t}\n\t\t\tif sourcesArr, ok := body["sources"].([]any); ok {\n\t\t\t\tvar parsed []map[string]any\n\t\t\t\tfor _, raw := range sourcesArr {\n\t\t\t\t\tif m, ok := raw.(map[string]any); ok { parsed = append(parsed, m) }\n\t\t\t\t}\n\t\t\t\tif len(parsed) > 0 { writeBridgeSources(parsed) }\n\t\t\t}\n\t\t\tsources := readBridgeSources()\n\t\t\twriteExtraURLSFile(sources)\n\t\t\twriteJSON(w, map[string]any{"status": "ok", "sources": sources})\n\t\tdefault:\n\t\t\tw.Header().Set("Allow", "GET, PUT")\n\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)\n\t\t}\n\t}\n}\n\nfunc componentSettingsAfterSave(name string, body map[string]any) {',
    "bridgeSourcesHandler function",
    guard='func bridgeSourcesHandler()',
)

# --- 4. Call initBridgeSources in init() function ---
repl(
    'func main() {',
    'func init() { initBridgeSources() }\n\nfunc main() {',
    "initBridgeSources in init()",
)

if changed:
    f.write_text(t)
print("[patch-bridge-sources] ok")
PY
