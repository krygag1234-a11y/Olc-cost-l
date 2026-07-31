#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <main.go> <main.tsx>" >&2
  exit 2
fi

main_go=$1
main_tsx=$2

python3 - "$main_go" "$main_tsx" <<'PY'
from pathlib import Path
import sys

go_path = Path(sys.argv[1])
tsx_path = Path(sys.argv[2])

go = go_path.read_text()

old_blocked = '''func (l *authLimiterType) Blocked(remote string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	state := l.state[remote]
	if time.Now().Before(state.until) {
		return true
	}
	return false
}'''
new_blocked = '''func (l *authLimiterType) Blocked(remote string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	state, ok := l.state[remote]
	if !ok {
		return false
	}
	now := time.Now()
	if now.Before(state.until) {
		return true
	}
	// A completed lockout starts a clean attempt window. Keeping count >= 5
	// made the very next typo immediately lock the address for another minute.
	if !state.until.IsZero() {
		delete(l.state, remote)
	}
	return false
}'''
if old_blocked in go:
    go = go.replace(old_blocked, new_blocked, 1)
elif new_blocked not in go:
    raise SystemExit("auth limiter Blocked anchor not found")

old_reply = '''if authLimiter.Blocked(remote) {
			http.Error(w, "too many auth failures", http.StatusTooManyRequests)
			return
		}'''
new_reply = '''if authLimiter.Blocked(remote) {
			w.Header().Set("Retry-After", "60")
			http.Error(w, "too many auth failures; retry in 60 seconds", http.StatusTooManyRequests)
			return
		}'''
if old_reply in go:
    go = go.replace(old_reply, new_reply)
elif new_reply not in go:
    raise SystemExit("auth limiter response anchors not found")

go_path.write_text(go)

tsx = tsx_path.read_text()
old_request = '''async function request(path: string, options?: RequestInit) {
  const res = await fetch(path, options);
  if (!res.ok) {
    if (res.status === 401) window.dispatchEvent(new Event("olcrtc-auth-required"));
    throw new Error((await res.text()).trim() || res.statusText);
  }
  return res;
}'''
new_request = '''async function request(path: string, options?: RequestInit) {
  const res = await fetch(path, options);
  if (!res.ok) {
    if (res.status === 401) window.dispatchEvent(new Event("olcrtc-auth-required"));
    if (res.status === 429) {
      const retry = Number.parseInt(res.headers.get("Retry-After") || "60", 10);
      throw new Error(`Слишком много неудачных попыток входа. Повторите через ${Number.isFinite(retry) ? retry : 60} секунд.`);
    }
    throw new Error((await res.text()).trim() || res.statusText);
  }
  return res;
}'''
if old_request in tsx:
    tsx = tsx.replace(old_request, new_request, 1)
elif new_request not in tsx:
    raise SystemExit("frontend request anchor not found")

tsx_path.write_text(tsx)
PY

echo "patched auth lockout reset and 429 UI"
