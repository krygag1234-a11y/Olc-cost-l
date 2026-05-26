#!/usr/bin/env bash
# Add /api/features endpoints to the manager so the admin UI can read and
# toggle zapret/tor/split/webtunnel via /opt/Olc-cost-l/scripts/olc-feature.sh.
#
# - GET  /api/features          → {"zapret":{"enabled":true,"active":"running"}, ...}
# - POST /api/features/{name}   → {"enabled":true|false}
#
# The list of feature names is whitelisted (no shell injection possible).
set -euo pipefail

MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-mgr-features] skip: $MAIN_GO not found"; exit 0; }

if grep -q '"/api/features"' "$MAIN_GO"; then
  echo "[patch-mgr-features] already applied"
  exit 0
fi

python3 - "$MAIN_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text()

# Make sure required imports exist
import_re = re.compile(r"import \((.*?)\)", re.DOTALL)
m = import_re.search(src)
if not m:
    raise SystemExit("[patch-mgr-features] import block not found")

imp = m.group(1)
need = ['"os/exec"', '"path/filepath"', '"strings"']
extras = []
for n in need:
    if n not in imp:
        extras.append(n)
if extras:
    new_imp = imp.rstrip() + "\n\t" + "\n\t".join(extras) + "\n"
    src = src.replace(imp, new_imp, 1)

# Anchor: insert handler registrations after /api/audit handler (stable line)
anchor = "\thandler.Handle(\"/api/audit\","
idx = src.find(anchor)
if idx < 0:
    # Fallback to /api/state
    anchor = "\thandler.Handle(\"/api/state\","
    idx = src.find(anchor)
if idx < 0:
    raise SystemExit("[patch-mgr-features] insert anchor not found")

# Find end of the audit handler block (matching closing ")))")
end_marker = "\t})))\n"
end_idx = src.find(end_marker, idx)
if end_idx < 0:
    raise SystemExit("[patch-mgr-features] anchor end not found")
insert_at = end_idx + len(end_marker)

snippet = """\thandler.Handle(\"/api/features\", adminAuth(http.HandlerFunc(featuresListHandler())))
\thandler.Handle(\"/api/features/\", adminAuth(http.HandlerFunc(featuresToggleHandler())))
"""
src = src[:insert_at] + snippet + src[insert_at:]

# Append helper functions at end of file
helpers = """

// featureNames is the whitelist of allowed toggles. Any other value is rejected
// before invoking the helper script — prevents argument injection into bash.
var featureNames = []string{\"zapret\", \"tor\", \"split\", \"webtunnel\"}

func featureScriptPath() string {
\tif p := os.Getenv(\"OLC_FEATURE_SCRIPT\"); p != \"\" {
\t\treturn p
\t}
\tcandidates := []string{
\t\t\"/opt/Olc-cost-l/scripts/olc-feature.sh\",
\t\t\"/usr/local/bin/olc-feature\",
\t}
\tfor _, c := range candidates {
\t\tif info, err := os.Stat(c); err == nil && !info.IsDir() {
\t\t\treturn c
\t\t}
\t}
\treturn \"\"
}

func readFeatureFlags() map[string]bool {
\tflags := map[string]bool{}
\tfor _, n := range featureNames {
\t\tflags[n] = true
\t}
\tdata, err := os.ReadFile(\"/etc/olcrtc-manager/features.env\")
\tif err != nil {
\t\treturn flags
\t}
\tfor _, line := range strings.Split(string(data), \"\\n\") {
\t\tline = strings.TrimSpace(line)
\t\tif line == \"\" || strings.HasPrefix(line, \"#\") {
\t\t\tcontinue
\t\t}
\t\teq := strings.IndexByte(line, '=')
\t\tif eq < 0 {
\t\t\tcontinue
\t\t}
\t\tkey := strings.TrimSpace(line[:eq])
\t\tval := strings.Trim(strings.TrimSpace(line[eq+1:]), \"\\\"'\")
\t\tswitch key {
\t\tcase \"OLCRTC_ENABLE_ZAPRET\":\n\t\t\tflags[\"zapret\"] = val != \"0\"
\t\tcase \"OLCRTC_ENABLE_TOR\":\n\t\t\tflags[\"tor\"] = val != \"0\"
\t\tcase \"OLCRTC_ENABLE_SPLIT\":\n\t\t\tflags[\"split\"] = val != \"0\"
\t\tcase \"OLCRTC_ENABLE_WEBTUNNEL\":\n\t\t\tflags[\"webtunnel\"] = val != \"0\"
\t\t}
\t}
\treturn flags
}

func featureLiveStatus() map[string]string {
\tout := map[string]string{}
\tunits := map[string]string{
\t\t\"tor\":      \"tor@default\",
\t\t\"zapret\":   \"zapret\",
\t\t\"manager\":  \"olcrtc-manager\",
\t}
\tfor name, unit := range units {
\t\tcmd := exec.Command(\"systemctl\", \"is-active\", unit)
\t\tb, _ := cmd.Output()
\t\tout[name] = strings.TrimSpace(string(b))
\t}
\tout[\"nfqws\"] = \"unknown\"
\tif b, err := exec.Command(\"pidof\", \"nfqws\").Output(); err == nil && len(strings.TrimSpace(string(b))) > 0 {
\t\tout[\"nfqws\"] = \"running\"
\t} else {
\t\tout[\"nfqws\"] = \"stopped\"
\t}
\tout[\"webtunnel\"] = \"missing\"
\tfor _, c := range []string{\"/usr/bin/webtunnel-client\", \"/usr/local/bin/webtunnel-client\"} {
\t\tif info, err := os.Stat(c); err == nil && !info.IsDir() {
\t\t\tout[\"webtunnel\"] = filepath.Base(c) + \" present\"
\t\t\tbreak
\t\t}
\t}
\treturn out
}

func featuresListHandler() func(w http.ResponseWriter, r *http.Request) {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodGet {
\t\t\tw.Header().Set(\"Allow\", http.MethodGet)
\t\t\thttp.Error(w, \"method not allowed\", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\twriteJSON(w, map[string]any{
\t\t\t\"flags\":  readFeatureFlags(),
\t\t\t\"live\":   featureLiveStatus(),
\t\t\t\"script\": featureScriptPath(),
\t\t})
\t}
}

func featuresToggleHandler() func(w http.ResponseWriter, r *http.Request) {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodPost {
\t\t\tw.Header().Set(\"Allow\", http.MethodPost)
\t\t\thttp.Error(w, \"method not allowed\", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tname := strings.TrimPrefix(r.URL.Path, \"/api/features/\")
\t\tname = strings.TrimSpace(name)
\t\tallowed := false
\t\tfor _, n := range featureNames {
\t\t\tif n == name {
\t\t\t\tallowed = true
\t\t\t\tbreak
\t\t\t}
\t\t}
\t\tif !allowed {
\t\t\thttp.Error(w, \"unknown feature\", http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tvar body struct {
\t\t\tEnabled bool `json:\"enabled\"`
\t\t}
\t\tif err := json.NewDecoder(r.Body).Decode(&body); err != nil {
\t\t\thttp.Error(w, \"invalid json body: \"+err.Error(), http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tscript := featureScriptPath()
\t\tif script == \"\" {
\t\t\thttp.Error(w, \"olc-feature.sh not installed\", http.StatusServiceUnavailable)
\t\t\treturn
\t\t}
\t\targ := \"off\"
\t\tif body.Enabled {
\t\t\targ = \"on\"
\t\t}
\t\tcmd := exec.Command(\"bash\", script, name, arg)
\t\tcmd.Env = append(os.Environ(), \"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\")
\t\tout, err := cmd.CombinedOutput()
\t\tresult := map[string]any{
\t\t\t\"feature\": name,
\t\t\t\"enabled\": body.Enabled,
\t\t\t\"output\":  string(out),
\t\t}
\t\tif err != nil {
\t\t\tresult[\"error\"] = err.Error()
\t\t\tw.WriteHeader(http.StatusInternalServerError)
\t\t}
\t\twriteJSON(w, result)
\t}
}
"""

if "func featuresListHandler" not in src:
    src += helpers

p.write_text(src)
print("[patch-mgr-features] applied")
PY
