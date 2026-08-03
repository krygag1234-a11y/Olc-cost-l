package main

import (
	"testing"
	"time"
)

func TestPeerSummaryFreshness(t *testing.T) {
	start := time.Date(2026, 8, 2, 20, 0, 0, 0, time.UTC)
	if peerSummaryIsCurrent(false, start, "2026-08-02T20:00:01Z") { t.Fatal("stopped process must not expose peers") }
	if peerSummaryIsCurrent(true, start, "2026-08-02T19:59:59Z") { t.Fatal("summary from previous run must be stale") }
	if !peerSummaryIsCurrent(true, start, "2026-08-02T20:00:01Z") { t.Fatal("fresh running summary rejected") }
}
