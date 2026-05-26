#!/usr/bin/env bash
# Retry j.Join on transient Prosody errors (Error loading roster, wait-jingle EOF,
# discover-services timeout). Each retry uses a fresh nick suffix to avoid
# Prosody session-ghost / mod_roster cache collisions, plus jittered backoff
# capped at 10s. Per-attempt context timeout keeps a stuck attempt from
# eating the whole liveness budget.
set -euo pipefail
JITSI_GO="${1:-${OLCRTC_REPO:-/tmp/olcrtc-src}/internal/engine/jitsi/jitsi.go}"
[[ -f "$JITSI_GO" ]] || exit 0

python3 - "$JITSI_GO" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

MARKER = "joinRetryAttempts"          # in our new code
LEGACY = "joinAndOpenBridgeWithRetry"  # from previous version (we'll replace it)

# Original upstream block
ORIG = """\tjSess, err := j.Join(ctx, j.Config{
\t\tHost:  s.host,
\t\tRoom:  s.room,
\t\tNick:  s.name,
\t\tDebug: logger.IsVerbose(),
\t})
\tif err != nil {
\t\treturn nil, fmt.Errorf("jitsi join: %w", err)
\t}"""

NEW = """\tconst joinRetryAttempts = 6
\tconst joinPerAttemptTimeout = 14 * time.Second
\tconst joinRetryBase = 1500 * time.Millisecond
\tconst joinRetryMax = 10 * time.Second
\tvar jSess *j.Session
\tvar err error
\tfor attempt := 1; attempt <= joinRetryAttempts; attempt++ {
\t\tactx, acancel := context.WithTimeout(ctx, joinPerAttemptTimeout)
\t\tnick := s.name
\t\tif attempt > 1 {
\t\t\t// Vary nick on retries: some Prosody deployments hit
\t\t\t// \"Error loading roster\" when a stale session JID lingers; a
\t\t\t// fresh nick forces a brand-new resource binding.
\t\t\tvar sb [2]byte
\t\t\tif _, rerr := rand.Read(sb[:]); rerr == nil {
\t\t\t\tnick = fmt.Sprintf(\"%s-%x\", s.name, sb)
\t\t\t}
\t\t}
\t\tjSess, err = j.Join(actx, j.Config{
\t\t\tHost:  s.host,
\t\t\tRoom:  s.room,
\t\t\tNick:  nick,
\t\t\tDebug: logger.IsVerbose(),
\t\t})
\t\tacancel()
\t\tif err == nil {
\t\t\tbreak
\t\t}
\t\tmsg := err.Error()
\t\tretriable := strings.Contains(msg, \"bind\") ||
\t\t\tstrings.Contains(msg, \"xmpp dial\") ||
\t\t\tstrings.Contains(msg, \"discover services\") ||
\t\t\tstrings.Contains(msg, \"allocate focus\") ||
\t\t\tstrings.Contains(msg, \"join muc\") ||
\t\t\tstrings.Contains(msg, \"wait jingle\") ||
\t\t\tstrings.Contains(msg, \"context deadline exceeded\")
\t\tif attempt >= joinRetryAttempts || !retriable {
\t\t\treturn nil, fmt.Errorf(\"jitsi join: %w\", err)
\t\t}
\t\td := time.Duration(attempt) * joinRetryBase
\t\tif d > joinRetryMax {
\t\t\td = joinRetryMax
\t\t}
\t\tvar jb [1]byte
\t\tif _, rerr := rand.Read(jb[:]); rerr == nil {
\t\t\tjitter := time.Duration(int64(jb[0])-128) * d / 512
\t\t\td += jitter
\t\t\tif d < 250*time.Millisecond {
\t\t\t\td = 250 * time.Millisecond
\t\t\t}
\t\t}
\t\tlogger.Warnf(\"jitsi: join attempt %d failed (%v), retrying in %s\", attempt, err, d.Round(time.Millisecond))
\t\tselect {
\t\tcase <-ctx.Done():
\t\t\treturn nil, ctx.Err()
\t\tcase <-time.After(d):
\t\t}
\t}
\tif err != nil {
\t\treturn nil, fmt.Errorf(\"jitsi join: %w\", err)
\t}"""

# Pattern to match older patched version: a `for attempt := 1; attempt <= 4`
# block we previously inserted.
LEGACY_RE = re.compile(
    r"\tvar jSess \*j\.Session\n"
    r"\tvar err error\n"
    r"\tfor attempt := 1; attempt <= 4; attempt\+\+ \{\n"
    r"(?:.*\n)*?"
    r"\tif err != nil \{\n"
    r"\t\treturn nil, fmt\.Errorf\(\"jitsi join: %w\", err\)\n"
    r"\t\}",
    re.MULTILINE,
)

if MARKER in t:
    print("[patch-jitsi-retry] already at v2 (marker present) — nothing to do")
    sys.exit(0)

# Replace either original block or legacy patched block
if ORIG in t:
    t = t.replace(ORIG, NEW, 1)
    src = "upstream"
elif LEGACY_RE.search(t):
    t = LEGACY_RE.sub(NEW.replace("\\", "\\\\"), t, count=1)
    src = "legacy v1"
else:
    raise SystemExit("[patch-jitsi-retry] j.Join block not found in expected form")

# Ensure crypto/rand is imported (alias 'rand')
import_block_re = re.compile(r"import \((.*?)\)", re.DOTALL)
m = import_block_re.search(t)
if not m:
    raise SystemExit("[patch-jitsi-retry] no import block")
imports = m.group(1)
if '"crypto/rand"' not in imports:
    new_imports = imports.replace('"context"', '"context"\n\t"crypto/rand"', 1)
    if new_imports == imports:
        # Fallback: append before close
        new_imports = imports.rstrip() + '\n\t"crypto/rand"\n'
    t = t.replace(imports, new_imports, 1)

# "time" is already imported in jitsi.go (used elsewhere), but verify
if '"time"' not in t:
    raise SystemExit("[patch-jitsi-retry] time import missing")

p.write_text(t)
print(f"[patch-jitsi-retry] applied v2 (from {src})")
PY
