#!/usr/bin/env bash
# Runtime YAML under /var/lib/olcrtc/manager-run (not /tmp) + prune stale files.
set -euo pipefail
MAIN="${1:-/tmp/olcrtc-manager-panel/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "managerRunDir()" in t:
    print("[patch-manager-runtime-dir] already patched")
    raise SystemExit(0)

insert = '''
func managerRunDir() string {
\tif v := strings.TrimSpace(os.Getenv("OLCRTC_MANAGER_RUN_DIR")); v != "" {
\t\treturn v
\t}
\treturn "/var/lib/olcrtc/manager-run"
}

func pruneManagerRunDir(dir string, keep int) {
\tentries, err := os.ReadDir(dir)
\tif err != nil {
\t\treturn
\t}
\ttype item struct {
\t\tname string
\t\tmod  time.Time
\t}
\tvar files []item
\tfor _, e := range entries {
\t\tif e.IsDir() || !strings.HasPrefix(e.Name(), "olcrtc-manager-srv-") {
\t\t\tcontinue
\t\t}
\t\tinfo, err := e.Info()
\t\tif err != nil {
\t\t\tcontinue
\t\t}
\t\tfiles = append(files, item{e.Name(), info.ModTime()})
\t}
\tif len(files) <= keep {
\t\treturn
\t}
\tsort.Slice(files, func(i, j int) bool { return files[i].mod.After(files[j].mod) })
\tfor _, f := range files[keep:] {
\t\t_ = os.Remove(filepath.Join(dir, f.name))
\t}
}
'''

if "func managerRunDir()" not in t:
    anchor = "func writeTempOlcrtcConfig"
    t = t.replace(anchor, insert + "\n" + anchor, 1)

old = """func writeTempOlcrtcConfig(prefix string, cfg olcrtcRuntimeConfig) (string, error) {
\tdata, err := yaml.Marshal(cfg)
\tif err != nil {
\t\treturn "", fmt.Errorf("marshal olcrtc config: %w", err)
\t}
\tfile, err := os.CreateTemp("", prefix+"-*.yaml")
\tif err != nil {
\t\treturn "", fmt.Errorf("create olcrtc config: %w", err)
\t}
\tpath := file.Name()
\tif _, err := file.Write(data); err != nil {
\t\t_ = file.Close()
\t\t_ = os.Remove(path)
\t\treturn "", fmt.Errorf("write olcrtc config: %w", err)
\t}
\tif err := file.Close(); err != nil {
\t\t_ = os.Remove(path)
\t\treturn "", fmt.Errorf("close olcrtc config: %w", err)
\t}
\treturn path, nil
}"""

new = """func writeTempOlcrtcConfig(prefix string, cfg olcrtcRuntimeConfig) (string, error) {
\tdata, err := yaml.Marshal(cfg)
\tif err != nil {
\t\treturn "", fmt.Errorf("marshal olcrtc config: %w", err)
\t}
\tdir := managerRunDir()
\tif err := os.MkdirAll(dir, 0o700); err != nil {
\t\treturn "", fmt.Errorf("mkdir manager run dir: %w", err)
\t}
\tpruneManagerRunDir(dir, 32)
\tfile, err := os.CreateTemp(dir, prefix+"-*.yaml")
\tif err != nil {
\t\treturn "", fmt.Errorf("create olcrtc config: %w", err)
\t}
\tpath := file.Name()
\tif _, err := file.Write(data); err != nil {
\t\t_ = file.Close()
\t\t_ = os.Remove(path)
\t\treturn "", fmt.Errorf("write olcrtc config: %w", err)
\t}
\tif err := file.Close(); err != nil {
\t\t_ = os.Remove(path)
\t\treturn "", fmt.Errorf("close olcrtc config: %w", err)
\t}
\treturn path, nil
}"""

if old not in t:
    raise SystemExit("writeTempOlcrtcConfig block not found")
t = t.replace(old, new, 1)

if '"sort"' not in t and "sort.Slice" in t:
    t = t.replace('import (\n', 'import (\n\t"sort"\n', 1)

p.write_text(t)
print("[patch-manager-runtime-dir] ok")
PY
