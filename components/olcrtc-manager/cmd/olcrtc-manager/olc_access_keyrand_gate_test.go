package main

import "testing"

func TestOlcType2OriginalClientIDRequiresAllowedBypass(t *testing.T) {
	cfg := Config{Clients: []Client{{
		ClientID:      "bs",
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
