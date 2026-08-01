#!/usr/bin/env bash
# Final access-control fixes:
# - global subscription '+' must remain keyrand after autosave;
# - subscription attempt cards wrap rather than forcing horizontal scrolling;
# - allow/ban IP rules accept exact IP, CIDR and inclusive IP ranges.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go> <path-to-main.tsx>}"
MAIN_TSX="${2:?usage: $0 <path-to-main.go> <path-to-main.tsx>}"
[[ -f "$MAIN_GO" && -f "$MAIN_TSX" ]] || { echo "[patch-access-plus-ip] ERROR: source not found"; exit 1; }

python3 - "$MAIN_GO" "$MAIN_TSX" <<'PY'
from pathlib import Path
import sys

go_path, tsx_path = map(Path, sys.argv[1:])
go = go_path.read_text()
tsx = tsx_path.read_text()

if '"net/netip"' not in go:
    anchor = '\t"net/http"'
    if anchor not in go:
        raise SystemExit('[patch-access-plus-ip] net/http import anchor not found')
    go = go.replace(anchor, anchor + '\n\t"net/netip"', 1)

helper_anchor = 'func olcAccessDecision(ac olcAccessControl, clientID, hwid, ip string)'
helper = r'''// olcAccessIPMatches supports a single address, CIDR, or an inclusive range
// "first-last". Rules are deliberately shared by global and per-client access.
func olcAccessIPMatches(rule, observed string) bool {
	rule = strings.TrimSpace(rule)
	observedAddr, err := netip.ParseAddr(strings.TrimSpace(observed))
	if rule == "" || err != nil {
		return false
	}
	observedAddr = observedAddr.Unmap()
	if dash := strings.Index(rule, "-"); dash > 0 && dash < len(rule)-1 {
		lo, loErr := netip.ParseAddr(strings.TrimSpace(rule[:dash]))
		hi, hiErr := netip.ParseAddr(strings.TrimSpace(rule[dash+1:]))
		if loErr != nil || hiErr != nil {
			return false
		}
		lo, hi = lo.Unmap(), hi.Unmap()
		return observedAddr.Is4() == lo.Is4() && lo.Is4() == hi.Is4() && lo.Compare(hi) <= 0 && observedAddr.Compare(lo) >= 0 && observedAddr.Compare(hi) <= 0
	}
	if prefix, prefixErr := netip.ParsePrefix(rule); prefixErr == nil {
		return prefix.Masked().Contains(observedAddr)
	}
	exact, exactErr := netip.ParseAddr(rule)
	return exactErr == nil && exact.Unmap() == observedAddr
}

'''
if 'func olcAccessIPMatches(rule, observed string)' not in go:
    if helper_anchor not in go:
        raise SystemExit('[patch-access-plus-ip] access decision anchor not found')
    go = go.replace(helper_anchor, helper + helper_anchor, 1)

old = 'bip.Enabled && bip.IP != "" && strings.TrimSpace(bip.IP) == ipt'
if old in go:
    go = go.replace(old, 'bip.Enabled && bip.IP != "" && olcAccessIPMatches(bip.IP, ipt)')
elif go.count('olcAccessIPMatches(bip.IP, ipt)') != 1:
    raise SystemExit('[patch-access-plus-ip] ban IP matcher missing')
old = 'aip.Enabled && aip.IP != "" && strings.TrimSpace(aip.IP) == ipt'
if old in go:
    go = go.replace(old, 'aip.Enabled && aip.IP != "" && olcAccessIPMatches(aip.IP, ipt)')
elif go.count('olcAccessIPMatches(aip.IP, ipt)') != 2:
    raise SystemExit('[patch-access-plus-ip] allow IP matcher missing')

# Global '+' was restored from the PUT response as monitor even though the
# backend had persisted keyrand. This is the global-only autosave regression.
old_mode = 'setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : "monitor");'
new_mode = 'setEnabled(!!b.enabled); setMode(b.mode === "enforce" ? "enforce" : b.mode === "keyrand" ? "keyrand" : "monitor");'
if old_mode in tsx:
    tsx = tsx.replace(old_mode, new_mode, 1)
elif new_mode not in tsx:
    raise SystemExit('[patch-access-plus-ip] global autosave mode anchor not found')

# The global subscription journal had min-w-0 without flex-1, so a long UA
# could enlarge the row and produce a horizontal scrollbar.
old_log = '''<div ref={listRef} onScroll={onScroll} className="grid max-h-56 gap-1 overflow-y-auto rounded border border-border bg-background p-2">'''
new_log = '''<div ref={listRef} onScroll={onScroll} className="grid max-h-56 gap-1 overflow-y-auto overflow-x-hidden rounded border border-border bg-background p-2">'''
if old_log in tsx:
    tsx = tsx.replace(old_log, new_log, 1)
elif new_log not in tsx:
    raise SystemExit('[patch-access-plus-ip] global journal container anchor not found')
old_row = 'className="flex items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]"'
new_row = 'className="flex min-w-0 items-center justify-between gap-2 rounded border border-border px-2 py-1 text-[11px]"'
if old_row in tsx:
    tsx = tsx.replace(old_row, new_row, 1)
elif new_row not in tsx:
    raise SystemExit('[patch-access-plus-ip] global journal row anchor not found')
old_body = '''<div className="min-w-0">
                        <div className="truncate font-mono">'''
new_body = '''<div className="min-w-0 flex-1">
                        <div className="break-all font-mono">'''
if old_body in tsx:
    tsx = tsx.replace(old_body, new_body, 1)
elif new_body not in tsx:
    raise SystemExit('[patch-access-plus-ip] global journal body anchor not found')
old_meta = '<div className="truncate text-muted-foreground">{aip} · подписка:'
new_meta = '<div className="break-words text-muted-foreground">{aip} · подписка:'
if old_meta in tsx:
    tsx = tsx.replace(old_meta, new_meta, 1)
elif new_meta not in tsx:
    raise SystemExit('[patch-access-plus-ip] global journal metadata anchor not found')

# Both global and per-client subscription IP widgets use the same stored field.
# Make the accepted formats visible where the user enters either allow or ban.
tsx = tsx.replace('placeholder="IP-адрес (напр. 203.0.113.7)"', 'placeholder="IP, CIDR или диапазон (203.0.113.7, /24, A-B)"')
tsx = tsx.replace('placeholder="IP-адрес"', 'placeholder="IP, CIDR или диапазон"')
tsx = tsx.replace('placeholder="IP-адрес (забанить)"', 'placeholder="IP, CIDR или диапазон (забанить)"')
if tsx.count('IP, CIDR или диапазон') < 4:
    raise SystemExit('[patch-access-plus-ip] expected global and per-client IP inputs')

# Put the explanation at every existing allow-IP help block. Exact matching is
# intentionally not used: later UI patches changed the wording independently.
needle = 'IP-список действует НЕЗАВИСИМО от списка устройств:'
if tsx.count(needle) < 2:
    raise SystemExit('[patch-access-plus-ip] IP help anchors missing')
if 'CIDR (`203.0.113.0/24`) или диапазон (`203.0.113.10-203.0.113.80`)' not in tsx:
    tsx = tsx.replace(needle, 'Поддерживаются IP, CIDR (`203.0.113.0/24`) или диапазон (`203.0.113.10-203.0.113.80`). ' + needle)

go_path.write_text(go)
tsx_path.write_text(tsx)
print('[patch-access-plus-ip] applied')
PY

# Generated unit test runs against the same actual helper during Linux builds.
TEST_GO="$(dirname "$MAIN_GO")/olc_access_ip_rules_test.go"
if [[ ! -f "$TEST_GO" ]] || ! grep -q 'TestOlcAccessIPRules' "$TEST_GO"; then
  cat > "$TEST_GO" <<'EOF'
package main

import "testing"

func TestOlcAccessIPRules(t *testing.T) {
	cases := []struct { rule, ip string; want bool }{
		{"203.0.113.7", "203.0.113.7", true},
		{"203.0.113.7", "203.0.113.8", false},
		{"203.0.113.0/24", "203.0.113.254", true},
		{"203.0.113.0/24", "203.0.114.1", false},
		{"203.0.113.10-203.0.113.80", "203.0.113.10", true},
		{"203.0.113.10 - 203.0.113.80", "203.0.113.80", true},
		{"203.0.113.10-203.0.113.80", "203.0.113.81", false},
		{"bad-rule", "203.0.113.7", false},
	}
	for _, tc := range cases {
		if got := olcAccessIPMatches(tc.rule, tc.ip); got != tc.want {
			t.Fatalf("rule %q, ip %q: got %t want %t", tc.rule, tc.ip, got, tc.want)
		}
	}
}
EOF
fi
