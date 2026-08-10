package main

import "testing"

func TestFilterPanelNotificationsSeparatesIssues(t *testing.T) {
	list := []map[string]any{
		{"id": "warning", "severity": "warning", "active": true},
		{"id": "error", "severity": "error", "status": "active"},
		{"id": "resolved", "severity": "warning", "active": false, "status": "resolved"},
		{"id": "info", "severity": "info", "active": true},
	}

	issues := filterPanelNotifications(list, "issues")
	if len(issues) != 2 || issues[0]["id"] != "warning" || issues[1]["id"] != "error" {
		t.Fatalf("unexpected issues view: %#v", issues)
	}

	notifications := filterPanelNotifications(list, "notifications")
	if len(notifications) != 2 || notifications[0]["id"] != "resolved" || notifications[1]["id"] != "info" {
		t.Fatalf("unexpected notifications view: %#v", notifications)
	}

	if all := filterPanelNotifications(list, "all"); len(all) != len(list) {
		t.Fatalf("all view lost events: %#v", all)
	}
}

func TestNotificationEventActiveLegacyCompatibility(t *testing.T) {
	if !notificationEventActive(map[string]any{"severity": "warning"}) {
		t.Fatal("legacy event without lifecycle fields must remain active")
	}
	if notificationEventActive(map[string]any{"status": "resolved"}) {
		t.Fatal("resolved event must not be active")
	}
}
