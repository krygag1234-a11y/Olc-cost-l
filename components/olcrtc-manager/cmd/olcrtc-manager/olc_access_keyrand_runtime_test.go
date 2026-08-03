package main

import (
  "path/filepath"
  "testing"
)

func TestOlcAccessGlobalKeyrandPersists(t *testing.T) {
  oldPath := olcAccessControlPath
  olcAccessControlPath = filepath.Join(t.TempDir(), "access-control.json")
  t.Cleanup(func() { olcAccessControlPath = oldPath })
  if err := olcAccessSave(olcAccessControl{Enabled: true, Mode: "keyrand"}); err != nil { t.Fatal(err) }
  got := olcAccessLoad()
  if !got.Enabled || got.Mode != "keyrand" { t.Fatalf("loaded enabled=%t mode=%q", got.Enabled, got.Mode) }
}

func TestOlcAccessKeyrandDecisionAndOriginalBypass(t *testing.T) {
  known := olcAllowedDevice{HWID: "known", Enabled: true}
  cases := []struct { name string; ac olcAccessControl; wantMode string; wantAllowed, wantBypass bool }{
    {"global-known-plus", olcAccessControl{Enabled: true, Mode: "keyrand", Devices: []olcAllowedDevice{known}}, "keyrand", true, true},
    {"global-unknown-plus", olcAccessControl{Enabled: true, Mode: "keyrand", Devices: []olcAllowedDevice{known}}, "keyrand", false, false},
    {"global-known-off", olcAccessControl{Enabled: true, Mode: "monitor", Devices: []olcAllowedDevice{known}}, "monitor", true, false},
    {"client-known-plus", olcAccessControl{Clients: map[string]*olcClientAccess{"c": &olcClientAccess{Mode: "keyrand", Allow: []olcAllowedDevice{known}}}}, "keyrand", true, true},
  }
  for _, tc := range cases {
    active, allowed, deny, mode := olcAccessDecision(tc.ac, "c", map[bool]string{true: "unknown", false: "known"}[tc.name == "global-unknown-plus"], "")
    if mode != tc.wantMode || allowed != tc.wantAllowed { t.Fatalf("%s: mode=%q allowed=%t", tc.name, mode, allowed) }
    if got := olcAccessOriginalIDBypass(mode, active, allowed, deny); got != tc.wantBypass { t.Fatalf("%s: bypass=%t", tc.name, got) }
  }
}
