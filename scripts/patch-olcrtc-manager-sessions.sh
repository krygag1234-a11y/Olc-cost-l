#!/usr/bin/env bash
# Persistent admin sessions + longer TTL (survives manager restart).
set -euo pipefail
MAIN="${1:-/tmp/olcrtc-manager-panel/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "sessionFilePath" in t:
    print("[patch-manager-sessions] already patched"); raise SystemExit(0)
    raise SystemExit(0)

helper = '''
const adminSessionTTL = 30 * 24 * time.Hour

func sessionFilePath(configPath string) string {
\tif v := strings.TrimSpace(os.Getenv("OLCRTC_MANAGER_SESSIONS")); v != "" {
\t\treturn v
\t}
\treturn filepath.Join("/var/lib/olcrtc", "manager-sessions.json")
}

func (s *sessionStore) loadFromDisk() {
\tpath := s.persistPath
\tif path == "" {
\t\treturn
\t}
\tdata, err := os.ReadFile(path)
\tif err != nil {
\t\treturn
\t}
\tvar raw map[string]string
\tif json.Unmarshal(data, &raw) != nil {
\t\treturn
\t}
\tnow := time.Now()
\ts.mu.Lock()
\tdefer s.mu.Unlock()
\tfor token, exp := range raw {
\t\tif t, err := time.Parse(time.RFC3339, exp); err == nil && now.Before(t) {
\t\t\ts.sessions[token] = t
\t\t}
\t}
}

func (s *sessionStore) persistLocked() {
\tif s.persistPath == "" {
\t\treturn
\t}
\traw := make(map[string]string, len(s.sessions))
\tfor token, exp := range s.sessions {
\t\traw[token] = exp.UTC().Format(time.RFC3339)
\t}
\tdata, err := json.Marshal(raw)
\tif err != nil {
\t\treturn
\t}
\t_ = os.MkdirAll(filepath.Dir(s.persistPath), 0o700)
\t_ = os.WriteFile(s.persistPath, data, 0o600)
}
'''

if "const adminSessionTTL" not in t:
    t = t.replace("type sessionStore struct {", helper + "\ntype sessionStore struct {", 1)

t = t.replace(
    "type sessionStore struct {\n\tmu       sync.Mutex\n\tsessions map[string]time.Time\n}",
    "type sessionStore struct {\n\tmu          sync.Mutex\n\tsessions    map[string]time.Time\n\tpersistPath string\n}",
    1,
)

t = t.replace(
    "func newSessionStore() *sessionStore {\n\treturn &sessionStore{sessions: make(map[string]time.Time)}\n}",
    """func newSessionStore() *sessionStore {
\ts := &sessionStore{sessions: make(map[string]time.Time), persistPath: sessionFilePath("")}
\ts.loadFromDisk()
\treturn s
}

func newSessionStoreForConfig(configPath string) *sessionStore {
\ts := &sessionStore{sessions: make(map[string]time.Time), persistPath: sessionFilePath(configPath)}
\ts.loadFromDisk()
\treturn s
}""",
    1,
)

t = t.replace("var adminSessions = newSessionStore()", "var adminSessions *sessionStore", 1)

if "adminSessions = newSessionStoreForConfig" not in t:
    t = t.replace(
        "\tadminConfigPath = configPath\n",
        "\tadminConfigPath = configPath\n\tadminSessions = newSessionStoreForConfig(configPath)\n",
        1,
    )

t = t.replace(
    "\ts.sessions[token] = time.Now().Add(12 * time.Hour)",
    "\ts.sessions[token] = time.Now().Add(adminSessionTTL)\n\ts.persistLocked()",
    1,
)

t = t.replace(
    "\tdelete(s.sessions, token)\n}",
    "\tdelete(s.sessions, token)\n\ts.persistLocked()\n}",
    2,
)

t = t.replace(
    "\ts.sessions = make(map[string]time.Time)\n}",
    "\ts.sessions = make(map[string]time.Time)\n\ts.persistLocked()\n}",
    1,
)

t = t.replace(
    "\t\tMaxAge:   int((12 * time.Hour).Seconds()),",
    "\t\tMaxAge:   int(adminSessionTTL.Seconds()),",
    1,
)

t = t.replace(
    "\t\tSameSite: http.SameSiteStrictMode,",
    "\t\tSameSite: http.SameSiteLaxMode,",
    2,
)

p.write_text(t)
if "persistLocked" not in p.read_text():
    print("patch-manager-sessions failed"); raise SystemExit(0)
print("[patch-manager-sessions] ok"); raise SystemExit(0)
PY
