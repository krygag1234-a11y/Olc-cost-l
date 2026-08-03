package main

import "testing"

func TestPatchedPeerSummaryParser(t *testing.T) {
	tests := []struct {
		name string
		line string
		count int
		devices int
		ok bool
	}{
		{"spaces", "Current peers count: 2, Devices: [phone laptop]", 2, 2, true},
		{"commas", "prefix Current peers count: 2, Devices: [phone, laptop]", 2, 2, true},
		{"empty", "Current peers count: 0, Devices: []", 0, 0, true},
		{"invalid count", "Current peers count: nope, Devices: []", 0, 0, false},
		{"missing bracket", "Current peers count: 1, Devices: [phone", 0, 0, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			count, devices, ok := parsePeerSummaryLine(tt.line)
			if ok != tt.ok || count != tt.count || len(devices) != tt.devices {
				t.Fatalf("got count=%d devices=%v ok=%v", count, devices, ok)
			}
		})
	}
}
