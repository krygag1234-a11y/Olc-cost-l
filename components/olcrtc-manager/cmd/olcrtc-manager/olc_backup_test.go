package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBackupExtraFilesCompleteness(t *testing.T) {
	files := backupExtraFiles("/etc/olcrtc-manager/config.json")
	want := []string{
		"panel_env", "features_env", "deploy_profile", "notification_settings",
		"instance_defaults", "access_control", "key_rotation", "key_randomization",
		"bridge_sources", "force_tor_domains", "ru_blocked_tor_domains",
		"custom_direct_domains", "ru_domains_extra", "split_discovered",
		"split_panel_hosts", "split_panel_cidrs", "zapret_exclude_domains",
		"zapret_force_domains", "zapret_strategy", "zapret_sync_cron",
		"tor_exit_env", "tor_exit_exclude_env", "torrc", "tor_bridges",
		"tor_user_bridges", "bridge_profiles", "bridge_pool_cron",
		"install_profile", "github_env", "access_attempts", "access_connections",
		"removed_zapret", "removed_tor", "removed_split", "removed_bridges", "removed_warp",
	}
	for _, key := range want {
		if files[key] == "" {
			t.Fatalf("backup path missing for %q", key)
		}
	}
}

func TestWriteBackupFileAtomicCreatesReversibleSnapshot(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "domains.txt")
	if err := os.WriteFile(path, []byte("old\n"), 0o640); err != nil {
		t.Fatal(err)
	}
	if err := writeBackupFileAtomic(path, []byte("new\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil || string(got) != "new\n" {
		t.Fatalf("restored file = %q, err=%v", got, err)
	}
	if info, err := os.Stat(path); err != nil || info.Mode().Perm() != 0o640 {
		t.Fatalf("mode not preserved: info=%v err=%v", info, err)
	}
	snapshots, err := filepath.Glob(path + ".bak-import-*")
	if err != nil || len(snapshots) != 1 {
		t.Fatalf("snapshots=%v err=%v", snapshots, err)
	}
	old, err := os.ReadFile(snapshots[0])
	if err != nil || string(old) != "old\n" {
		t.Fatalf("snapshot = %q, err=%v", old, err)
	}
}

func TestRestoreBackupExtraAllKinds(t *testing.T) {
	dir := t.TempDir()

	objectPath := filepath.Join(dir, "object.json")
	_ = os.WriteFile(objectPath, []byte(`{"keep":1,"replace":"old"}`), 0o600)
	if !restoreBackupExtra(objectPath, map[string]any{
		"kind": "json", "value": map[string]any{"replace": "new"},
	}) {
		t.Fatal("json object restore failed")
	}
	var object map[string]any
	data, _ := os.ReadFile(objectPath)
	_ = json.Unmarshal(data, &object)
	if object["keep"] == nil || object["replace"] != "new" {
		t.Fatalf("json object not merged: %#v", object)
	}

	arrayPath := filepath.Join(dir, "array.json")
	_ = os.WriteFile(arrayPath, []byte(`{"old":true}`), 0o600)
	if !restoreBackupExtra(arrayPath, map[string]any{
		"kind": "json", "value": []any{"a", "b"},
	}) {
		t.Fatal("json array restore failed")
	}
	var array []string
	data, _ = os.ReadFile(arrayPath)
	if json.Unmarshal(data, &array) != nil || len(array) != 2 || array[1] != "b" {
		t.Fatalf("json array not restored: %q", data)
	}

	envPath := filepath.Join(dir, "panel.env")
	_ = os.WriteFile(envPath, []byte("KEEP=1\nCHANGE=old\n"), 0o600)
	if !restoreBackupExtra(envPath, map[string]any{
		"kind": "env", "values": map[string]any{"CHANGE": "new", "ADD": "2"},
	}) {
		t.Fatal("env restore failed")
	}
	data, _ = os.ReadFile(envPath)
	envText := string(data)
	if !strings.Contains(envText, "KEEP=1") || !strings.Contains(envText, `CHANGE="new"`) || !strings.Contains(envText, `ADD="2"`) {
		t.Fatalf("env not merged: %q", envText)
	}

	textPath := filepath.Join(dir, "domains.txt")
	_ = os.WriteFile(textPath, []byte("old.example\n"), 0o600)
	if !restoreBackupExtra(textPath, map[string]any{"kind": "text", "value": "a.example\nb.example\n"}) {
		t.Fatal("text restore failed")
	}
	data, _ = os.ReadFile(textPath)
	if string(data) != "a.example\nb.example\n" {
		t.Fatalf("text not restored exactly: %q", data)
	}
}

func TestBackupHasRoomKey(t *testing.T) {
	withBinding := map[string]any{"clients": []any{map[string]any{
		"locations": []any{map[string]any{"endpoint": map[string]any{"room_id": "room", "key": "secret"}}},
	}}}
	if !backupHasRoomKey(withBinding) {
		t.Fatal("active room+key binding was not detected")
	}
	if backupHasRoomKey(map[string]any{"endpoint": map[string]any{"room_id": "room", "key": ""}}) {
		t.Fatal("incomplete binding must not trigger foreign-host guard")
	}
}

func TestBackupImportForeignHostRequiresExplicitConfirmation(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.json")
	original := []byte("{\"sentinel\":\"old\"}\n")
	if err := os.WriteFile(configPath, original, 0o600); err != nil {
		t.Fatal(err)
	}
	envelope := map[string]any{
		"olc_backup": true, "schema_version": 1, "source_host_id": "definitely-another-host",
		"config": map[string]any{"clients": []any{map[string]any{
			"client-id": "clone", "locations": []any{map[string]any{
				"endpoint": map[string]any{"room_id": "same-room", "key": "same-key"},
			}},
		}}},
	}
	body, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/backup/import", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	backupImportHandler(configPath).ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("unconfirmed foreign import status=%d body=%s", rec.Code, rec.Body.String())
	}
	after, _ := os.ReadFile(configPath)
	if !bytes.Equal(after, original) {
		t.Fatalf("guarded import modified config: %s", after)
	}

	req = httptest.NewRequest(http.MethodPost, "/api/backup/import?confirm_foreign_host=1", bytes.NewReader(body))
	rec = httptest.NewRecorder()
	backupImportHandler(configPath).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("confirmed foreign import status=%d body=%s", rec.Code, rec.Body.String())
	}
	after, _ = os.ReadFile(configPath)
	if !bytes.Contains(after, []byte("same-room")) {
		t.Fatalf("confirmed import did not restore config: %s", after)
	}
}
