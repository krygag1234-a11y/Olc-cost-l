package main

import "testing"

func TestParseFeatureFlagsMissingFileDefaultsOptionalModulesOff(t *testing.T) {
	flags := parseFeatureFlags(nil)
	for _, name := range []string{"zapret", "tor", "split", "bridges", "webtunnel", "warp"} {
		if flags[name] {
			t.Fatalf("%s defaulted to enabled without an installed profile", name)
		}
	}
	if !flags["olcrtc"] {
		t.Fatal("manager core must remain enabled")
	}
}

func TestParseFeatureFlagsKeepsModuleAndSubmoduleSeparate(t *testing.T) {
	flags := parseFeatureFlags([]byte(`
OLCRTC_ENABLE_TOR=1
OLCRTC_ENABLE_BRIDGES=1
OLCRTC_ENABLE_WEBTUNNEL=0
`))
	if !flags["tor"] || !flags["bridges"] {
		t.Fatalf("expected tor and bridges enabled: %#v", flags)
	}
	if flags["webtunnel"] {
		t.Fatalf("webtunnel submodule must stay disabled: %#v", flags)
	}
}

func TestParseFeatureFlagsMigratesLegacyWebtunnelAggregate(t *testing.T) {
	flags := parseFeatureFlags([]byte("OLCRTC_ENABLE_WEBTUNNEL=1\n"))
	if !flags["bridges"] || !flags["webtunnel"] {
		t.Fatalf("legacy aggregate was not migrated in memory: %#v", flags)
	}
}

func TestParseFeatureFlagsExplicitBridgesWins(t *testing.T) {
	flags := parseFeatureFlags([]byte(`
OLCRTC_ENABLE_BRIDGES=0
OLCRTC_ENABLE_WEBTUNNEL=1
`))
	if flags["bridges"] || !flags["webtunnel"] {
		t.Fatalf("module and submodule state were collapsed: %#v", flags)
	}
}
