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
