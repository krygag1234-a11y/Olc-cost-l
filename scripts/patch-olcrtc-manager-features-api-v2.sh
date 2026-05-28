#!/usr/bin/env bash
# Features API: no HTTP 500 when toggle saved but manager self-restart kills the handler.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'featuresToggleSucceeded' "$MAIN_GO" && { echo "[patch-features-api-v2] already applied"; exit 0; }
grep -q 'featuresToggleHandler' "$MAIN_GO" || exit 0

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

# Add helper before featuresListHandler
helper = """
func featuresToggleSucceeded(name string, wantEnabled bool, scriptErr error, output string) bool {
\tif scriptErr == nil {
\t\treturn true
\t}
\tflags := readFeatureFlags()
\tif flags[name] == wantEnabled {
\t\treturn true
\t}
\tmsg := scriptErr.Error() + " " + output
\tif strings.Contains(msg, \"signal: terminated\") && flags[name] == wantEnabled {
\t\treturn true
\t}
\tif name == \"split\" && wantEnabled && flags[\"split\"] {
\t\treturn true
\t}
\tif name == \"tor\" && !wantEnabled && !flags[\"tor\"] {
\t\treturn true
\t}
\treturn false
}

"""

anchor = "func featuresListHandler()"
if anchor not in t:
    print("[patch-features-api-v2] featuresListHandler not found"); raise SystemExit(0)
if "func featuresToggleSucceeded" not in t:
    t = t.replace(anchor, helper + anchor, 1)

old_block = """\t\tcmd := exec.Command(\"bash\", script, name, arg)
\t\tcmd.Env = append(os.Environ(), \"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\")
\t\tout, err := cmd.CombinedOutput()
\t\tresult := map[string]any{
\t\t\t\"feature\": name,
\t\t\t\"enabled\": body.Enabled,
\t\t\t\"output\":  string(out),
\t\t}
\t\tif err != nil {
\t\t\tresult[\"error\"] = err.Error()
\t\t\t// split on may warn in setup-split-ru but still enable routing lists
\t\t\tif !(name == \"split\" && body.Enabled && readFeatureFlags()[\"split\"]) {
\t\t\t\tw.WriteHeader(http.StatusInternalServerError)
\t\t\t}
\t\t}
\t\twriteJSON(w, result)"""

new_block = """\t\tctx, cancel := context.WithTimeout(r.Context(), 3*time.Minute)
\t\tdefer cancel()
\t\tcmd := exec.CommandContext(ctx, \"bash\", script, name, arg)
\t\tcmd.Env = append(os.Environ(),
\t\t\t\"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\",
\t\t\t\"OLC_FEATURE_NO_MANAGER_RESTART=0\",
\t\t)
\t\tout, err := cmd.CombinedOutput()
\t\tresult := map[string]any{
\t\t\t\"feature\": name,
\t\t\t\"enabled\": body.Enabled,
\t\t\t\"output\":  string(out),
\t\t\t\"flags\":   readFeatureFlags(),
\t\t}
\t\tif err != nil {
\t\t\tresult[\"error\"] = err.Error()
\t\t\tif !featuresToggleSucceeded(name, body.Enabled, err, string(out)) {
\t\t\t\tw.WriteHeader(http.StatusInternalServerError)
\t\t\t} else {
\t\t\t\tresult[\"warning\"] = \"toggle applied; manager may restart in a few seconds\"
\t\t\t}
\t\t}
\t\twriteJSON(w, result)"""

if old_block in t:
    t = t.replace(old_block, new_block, 1)
else:
    # minimal block without split tolerant
    old2 = """\t\tcmd := exec.Command(\"bash\", script, name, arg)
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
\t\twriteJSON(w, result)"""
    if old2 not in t:
        print("[patch-features-api-v2] toggle handler block not found"); raise SystemExit(0)
    t = t.replace(old2, new_block, 1)

if '"context"' not in t.split("import (")[1].split(")")[0]:
    t = t.replace('"context"\n', '"context"\n', 1)
if '"time"' not in t.split("import (")[1].split(")")[0]:
    t = t.replace('"strings"\n', '"strings"\n\t"time"\n', 1)

p.write_text(t)
print("[patch-features-api-v2] ok"); raise SystemExit(0)
PY
