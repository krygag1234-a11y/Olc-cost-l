package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)


func TestBackupFirstRunImportRestoresCredentialsAndSession(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(configPath, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	oldSessions := adminSessions
	oldSessionPath := os.Getenv("OLCRTC_MANAGER_SESSIONS")
	oldUser := os.Getenv("OLCRTC_MANAGER_USER")
	oldPass := os.Getenv("OLCRTC_MANAGER_PASS")
	t.Cleanup(func() {
		adminSessions = oldSessions
		_ = os.Setenv("OLCRTC_MANAGER_SESSIONS", oldSessionPath)
		_ = os.Setenv("OLCRTC_MANAGER_USER", oldUser)
		_ = os.Setenv("OLCRTC_MANAGER_PASS", oldPass)
	})
	_ = os.Setenv("OLCRTC_MANAGER_SESSIONS", filepath.Join(dir, "sessions.json"))
	_ = os.Unsetenv("OLCRTC_MANAGER_USER")
	_ = os.Unsetenv("OLCRTC_MANAGER_PASS")
	adminSessions = newSessionStoreForConfig(configPath)

	envelope := map[string]any{
		"olc_backup": true,
		"schema_version": 1,
		"config": map[string]any{},
		"extras": map[string]any{
			"panel_env": map[string]any{
				"kind": "env",
				"values": map[string]any{
					"OLCRTC_MANAGER_USER": "restored-admin",
					"OLCRTC_MANAGER_PASS": "restored-password",
				},
			},
		},
	}
	body, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/backup/import-first-run", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	backupFirstRunImportHandler(configPath).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("first-run import status=%d body=%s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Set-Cookie") == "" {
		t.Fatal("first-run import did not establish an admin session")
	}
	user, pass := adminCredentials(configPath)
	if user != "restored-admin" || pass != "restored-password" {
		t.Fatalf("restored credentials user=%q pass=%q", user, pass)
	}

	req = httptest.NewRequest(http.MethodPost, "/api/backup/import-first-run", bytes.NewReader(body))
	rec = httptest.NewRecorder()
	backupFirstRunImportHandler(configPath).ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("configured first-run import status=%d, want 409", rec.Code)
	}
}
