#!/usr/bin/env bash
set -euo pipefail

repo=${1:?usage: $0 <olcrtc-repo-root>}
hook="$repo/internal/app/session/olc_access_hook.go"
watcher="$repo/internal/server/olc_ban_watcher.go"
test_file="$repo/internal/app/session/olc_access_keyrand_test.go"

python3 - "$hook" "$watcher" "$test_file" <<'PY'
from pathlib import Path
import sys

hook_path, watcher_path, test_path = map(Path, sys.argv[1:])
hook = hook_path.read_text()

old_init = '''func init() {
	server.OlcBanRecheck = olcAccessConnDecide
}'''
new_init = '''func init() {
	server.OlcBanRecheck = func(deviceID string, keyClass int) bool {
		return olcAccessDecideConnFull(deviceID, keyClass, true)
	}
}'''
if old_init in hook:
    hook = hook.replace(old_init, new_init, 1)
elif new_init not in hook:
    raise SystemExit("OlcBanRecheck init anchor not found")

old_keyrand = '''		if recheck {
			return true
		}
		return keyClass == 1'''
new_keyrand = '''		// keyClass < 0 means crypto-key randomization is not active for this
		// instance (scope=client_id or randomization disabled). In that case the
		// + mode restricts only client_id and keeps original crypto keys valid.
		if keyClass < 0 {
			return true
		}
		return keyClass == 1'''
if old_keyrand in hook:
    hook = hook.replace(old_keyrand, new_keyrand, 1)
elif new_keyrand not in hook:
    raise SystemExit("keyrand recheck bypass anchor not found")

hook = hook.replace(
    '// режима). keyClass: -1 ранд выкл / 0 ориг / 1 ранд. recheck=true (ban-watcher):\n'
    '// не отклонять «неизвестных» по классу ключа (живая сессия прошла handshake). fail-open.',
    '// режима). keyClass: -1 crypto-рандомизация не действует / 0 оригинальный / 1 рандомизированный.\n'
    '// Handshake и live recheck используют одну матрицу; выключение разрешения немедленно кикает\n'
    '// сессию, подключённую по оригинальному ключу. Параметр recheck сохранён для совместимости.',
    1,
)
hook_path.write_text(hook)

watcher = watcher_path.read_text()
replacements = [
    ('var OlcBanRecheck func(deviceID string) bool',
     'var OlcBanRecheck func(deviceID string, keyClass int) bool'),
    ('type peerRef struct{ id, dev string }',
     'type peerRef struct {\n\t\tid, dev string\n\t\tkeyClass int\n\t}'),
    ('singleSID := s.sessionID\n\tcur := s.session',
     'singleSID := s.sessionID\n\tsingleConn := s.controlConn\n\tif singleConn == nil {\n\t\tsingleConn = s.conn\n\t}\n\tsingleKeyClass := olcKeyClass(singleConn)\n\tcur := s.session'),
    ('peers = append(peers, peerRef{id: id, dev: ps.deviceID})',
     'peerConn := ps.controlConn\n\t\t\tif peerConn == nil {\n\t\t\t\tpeerConn = ps.conn\n\t\t\t}\n\t\t\tpeers = append(peers, peerRef{id: id, dev: ps.deviceID, keyClass: olcKeyClass(peerConn)})'),
    ('if !recheck(p.dev) {', 'if !recheck(p.dev, p.keyClass) {'),
    ('!peerDevs[singleDev] && !recheck(singleDev) {',
     '!peerDevs[singleDev] && !recheck(singleDev, singleKeyClass) {'),
]
for old, new in replacements:
    if old in watcher:
        watcher = watcher.replace(old, new, 1)
    elif new not in watcher:
        raise SystemExit(f"watcher anchor not found: {old[:60]}")
watcher_path.write_text(watcher)

if test_path.exists():
    tests = test_path.read_text()
    tests = tests.replace(
        '{"unknown recheck", "unknown", 0, true, true},',
        '{"unknown original recheck", "unknown", 0, true, false},\n'
        '\t\t{"unknown randomized recheck", "unknown", 1, true, true},\n'
        '\t\t{"client-id-only scope", "unknown", -1, true, true},',
        1,
    )
    test_path.write_text(tests)
PY

gofmt -w "$hook" "$watcher"
[[ ! -f "$test_file" ]] || gofmt -w "$test_file"

cat > "$(dirname "$hook")/olc_access_live_keyclass_test.go" <<'GOTEST'
package session

import (
	"os"
	"path/filepath"
	"testing"
)

func TestOlcAccessLiveKeyClassMatrix(t *testing.T) {
	oldPath := olcAccessControlPath
	oldClient := os.Getenv("OLCRTC_CLIENT_ID")
	oldRoom := os.Getenv("OLCRTC_ROOM_ID")
	t.Cleanup(func() {
		olcAccessControlPath = oldPath
		_ = os.Setenv("OLCRTC_CLIENT_ID", oldClient)
		_ = os.Setenv("OLCRTC_ROOM_ID", oldRoom)
	})
	olcAccessControlPath = filepath.Join(t.TempDir(), "access-control.json")
	_ = os.Setenv("OLCRTC_CLIENT_ID", "matrix-client")
	_ = os.Setenv("OLCRTC_ROOM_ID", "matrix-room")

	writeMode := func(mode string) {
		t.Helper()
		body := `{"enabled":false,"clients":{"matrix-client":{"conn_mode":"` + mode +
			`","conn_scope":"all","conn_allow":[{"hwid":"allowed","enabled":true},{"hwid":"disabled","enabled":false}],` +
			`"conn_ban":[{"hwid":"banned","enabled":true}]}}}`
		if err := os.WriteFile(olcAccessControlPath, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	writeMode("keyrand")
	cases := []struct {
		name     string
		device   string
		keyClass int
		want     bool
	}{
		{"allowed original", "allowed", 0, true},
		{"disabled original is kicked", "disabled", 0, false},
		{"unknown original is kicked", "unknown", 0, false},
		{"unknown randomized remains", "unknown", 1, true},
		{"client-id-only keeps original crypto", "unknown", -1, true},
		{"ban overrides randomized", "banned", 1, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := olcAccessDecideConnFull(tc.device, tc.keyClass, true); got != tc.want {
				t.Fatalf("live decision=%v want=%v", got, tc.want)
			}
		})
	}

	writeMode("enforce")
	if olcAccessDecideConnFull("unknown", 1, true) {
		t.Fatal("enforce must reject an unknown device even with a randomized key")
	}
	if !olcAccessDecideConnFull("allowed", 0, true) {
		t.Fatal("enforce must keep an allowed original-key device")
	}
}
GOTEST
gofmt -w "$(dirname "$hook")/olc_access_live_keyclass_test.go"
echo "patched live access recheck with current connection key class"
