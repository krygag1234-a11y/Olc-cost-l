#!/usr/bin/env bash
set -euo pipefail

main_go=${1:?usage: $0 <main.go>}

python3 - "$main_go" <<'PY'
from pathlib import Path
import re
import sys

main = Path(sys.argv[1])
text = main.read_text()

# Historical type-2 code let the original client_id through before the access
# resolver could distinguish an allowed device.  Both types must reject it by
# default; only the explicit allowlist bypass may resolve the original id.
pattern = re.compile(
    r'''\t\t\tcase 2:\n(?:\t\t\t\t//[^\n]*\n)+\t\t\t\treturn requestedID, nil\n\t\t\tdefault:\n(?:\t\t\t\t//[^\n]*\n)+\t\t\t\treturn "", errors\.New\("not found"\)'''
)
replacement = '''\t\t\tcase 1, 2:
\t\t\t\t// Both types hide the original client_id. Only an explicitly
\t\t\t\t// allowed device may use it via olcResolveClientIDWithAccess.
\t\t\t\treturn "", errors.New("not found")'''
text, count = pattern.subn(replacement, text, count=1)
if count == 0 and 'case 1, 2:' not in text:
    raise SystemExit('type-2 original client-id gate anchor not found')
main.write_text(text)

test = main.with_name('olc_access_keyrand_gate_test.go')
test.write_text(r'''package main

import "testing"

func TestOlcType2OriginalClientIDRequiresAllowedBypass(t *testing.T) {
	cfg := Config{Clients: []Client{{
		ClientID: "bs",
		Randomization: &ClientRandomization{Enabled: true, RandType: 2},
	}}}
	if got, err := resolveClientID("bs", cfg); err == nil {
		t.Fatalf("unknown device resolved original type-2 client id: got=%q", got)
	}
	if got, err := olcResolveClientIDWithAccess("bs", cfg, false); err == nil {
		t.Fatalf("non-bypass access resolved original type-2 client id: got=%q", got)
	}
	if got, err := olcResolveClientIDWithAccess("bs", cfg, true); err != nil || got != "bs" {
		t.Fatalf("allowed bypass = (%q, %v), want (bs, nil)", got, err)
	}
}
''')
PY

gofmt -w "$(dirname "$main_go")/olc_access_keyrand_gate_test.go"
echo "patched type-2 original client-id access gate"
