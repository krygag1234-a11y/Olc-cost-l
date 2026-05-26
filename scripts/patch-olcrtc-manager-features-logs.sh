#!/usr/bin/env bash
# GET /api/features/logs/{name} — tail feature-related log files for the panel UI.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'featuresLogsHandler' "$MAIN_GO" && { echo "[patch-features-logs] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

snippet_route = '\thandler.Handle("/api/features/logs/", adminAuth(http.HandlerFunc(featuresLogsHandler())))\n'

anchor = '\thandler.Handle("/api/features/", adminAuth(http.HandlerFunc(featuresToggleHandler())))'
if snippet_route.strip() not in t:
    if anchor not in t:
        raise SystemExit("[patch-features-logs] features routes not found")
    t = t.replace(anchor, snippet_route + anchor, 1)

helpers = """
func featureLogPaths(name string) []string {
\tswitch name {
\tcase "zapret":
\t\treturn []string{"/var/log/olcrtc-zapret-sync.log", "/var/log/syslog"}
\tcase "tor":
\t\treturn []string{"/var/log/olcrtc-healthcheck.log", "/var/log/tor/log"}
\tcase "split":
\t\treturn []string{"/var/log/olcrtc-zapret-sync.log", "/var/log/olcrtc-healthcheck.log"}
\tcase "webtunnel":
\t\treturn []string{"/var/log/olcrtc-healthcheck.log"}
\tdefault:
\t\treturn nil
\t}
}

func tailFileLines(path string, maxLines int) ([]string, error) {
\tf, err := os.Open(path)
\tif err != nil {
\t\treturn nil, err
\t}
\tdefer f.Close()
\tvar lines []string
\tscanner := bufio.NewScanner(f)
\tfor scanner.Scan() {
\t\tlines = append(lines, scanner.Text())
\t\tif len(lines) > maxLines*2 {
\t\t\tlines = lines[len(lines)-maxLines:]
\t\t}
\t}
\tif err := scanner.Err(); err != nil {
\t\treturn nil, err
\t}
\tif len(lines) > maxLines {
\t\tlines = lines[len(lines)-maxLines:]
\t}
\treturn lines, nil
}

func featuresLogsHandler() func(w http.ResponseWriter, r *http.Request) {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodGet {
\t\t\tw.Header().Set("Allow", http.MethodGet)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tname := strings.TrimPrefix(r.URL.Path, "/api/features/logs/")
\t\tname = strings.TrimSpace(strings.Trim(name, "/"))
\t\tallowed := false
\t\tfor _, n := range featureNames {
\t\t\tif n == name {
\t\t\t\tallowed = true
\t\t\t\tbreak
\t\t\t}
\t\t}
\t\tif !allowed {
\t\t\thttp.Error(w, "unknown feature", http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tvar usedPath string
\t\tvar lines []string
\t\tfor _, path := range featureLogPaths(name) {
\t\t\tgot, err := tailFileLines(path, 200)
\t\t\tif err != nil {
\t\t\t\tcontinue
\t\t\t}
\t\t\tusedPath = path
\t\t\tlines = got
\t\t\tbreak
\t\t}
\t\tif lines == nil {
\t\t\tlines = []string{"(log file not found — run olc-update or check /var/log/olcrtc-*)"}
\t\t}
\t\twriteJSON(w, map[string]any{"feature": name, "path": usedPath, "lines": lines})
\t}
}
"""

if "func featuresLogsHandler" not in t:
    if '"bufio"' not in t.split("import (")[1].split(")")[0]:
        t = t.replace('"bytes"\n', '"bytes"\n\t"bufio"\n', 1)
    anchor2 = "func featuresListHandler()"
    t = t.replace(anchor2, helpers + "\n" + anchor2, 1)

p.write_text(t)
print("[patch-features-logs] ok")
PY
