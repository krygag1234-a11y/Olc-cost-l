#!/usr/bin/env bash
set -euo pipefail

main_go=${1:?usage: $0 <main.go> <main.tsx>}
main_tsx=${2:?usage: $0 <main.go> <main.tsx>}

python3 - "$main_go" "$main_tsx" <<'PY'
from pathlib import Path
import sys

go_path, tsx_path = map(Path, sys.argv[1:])
go = go_path.read_text()

route = '\thandler.Handle("/api/backup/import", adminAuth(http.HandlerFunc(backupImportHandler(configPath))))'
route_new = route + '\n\thandler.Handle("/api/backup/import-first-run", http.HandlerFunc(backupFirstRunImportHandler(configPath)))'
if '/api/backup/import-first-run' not in go:
    if route not in go:
        raise SystemExit("backup import route anchor not found")
    go = go.replace(route, route_new, 1)

handler_anchor = 'func backupImportHandler(configPath string) http.HandlerFunc {'
first_run_handler = '''// backupFirstRunImportHandler solves the clean-install bootstrap: a complete
// backup contains panel.env credentials, but the normal import route requires
// those credentials. This route exists only while no panel credentials exist.
func backupFirstRunImportHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, pass := adminCredentials(configPath)
		if user != "" || pass != "" {
			writeJSONStatus(w, http.StatusConflict, map[string]string{"error": "first-run import is available only before panel setup"})
			return
		}
		q := r.URL.Query()
		q.Set("first_run", "1")
		r.URL.RawQuery = q.Encode()
		backupImportHandler(configPath).ServeHTTP(w, r)
	}
}

'''
if 'func backupFirstRunImportHandler(' not in go:
    if handler_anchor not in go:
        raise SystemExit("backupImportHandler anchor not found")
    go = go.replace(handler_anchor, first_run_handler + handler_anchor, 1)

success_anchor = '''		sort.Strings(restored)
		appendAudit(configPath, "backup_import", strings.Join(restored, ","))
		writeJSON(w, map[string]any{'''
success_new = '''		sort.Strings(restored)
		appendAudit(configPath, "backup_import", strings.Join(restored, ","))
		if r.URL.Query().Get("first_run") == "1" {
			token, err := adminSessions.Create()
			if err != nil {
				writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			setSessionCookie(w, token)
		}
		writeJSON(w, map[string]any{'''
if 'r.URL.Query().Get("first_run") == "1"' not in go:
    if success_anchor not in go:
        raise SystemExit("backup import success anchor not found")
    go = go.replace(success_anchor, success_new, 1)
go_path.write_text(go)

tsx = tsx_path.read_text()
start = tsx.find('function LoginView(')
end = tsx.find('\nfunction ClientSettingsFields(', start)
if start < 0 or end < 0:
    raise SystemExit("LoginView block not found")
login = tsx[start:end]

if 'firstRunBackupRef' not in login:
    login = login.replace(
        '  const [busy, setBusy] = useState(false);',
        '  const [busy, setBusy] = useState(false);\n  const firstRunBackupRef = useRef<HTMLInputElement | null>(null);',
        1,
    )
    return_anchor = '  return (\n    <div className="grid min-h-screen place-items-center bg-background px-5">'
    restore_fn = '''  const restoreFirstRunBackup = async (file: File) => {
    setBusy(true); setError("");
    try {
      const body = await file.text();
      const send = async (confirmed: boolean) => {
        const suffix = confirmed ? "?confirm_foreign_host=1" : "";
        const res = await fetch("/api/backup/import-first-run" + suffix, { method: "POST", headers: { "Content-Type": "application/json" }, body });
        const data = await res.json().catch(() => ({} as any));
        return { res, data };
      };
      let { res, data } = await send(false);
      if (res.status === 409 && data?.code === "foreign_host_confirmation_required") {
        if (!window.confirm("Бекап создан на другом VPS и содержит активные room+key. Импортировать его на этот сервер?")) return;
        ({ res, data } = await send(true));
      }
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      await onLogin();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
      if (firstRunBackupRef.current) firstRunBackupRef.current.value = "";
    }
  };

'''
    if return_anchor not in login:
        raise SystemExit("LoginView return anchor not found")
    login = login.replace(return_anchor, restore_fn + return_anchor, 1)

    error_anchor = '        {error && <div className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">{error}</div>}'
    restore_ui = '''        {setupRequired && (
          <div className="grid gap-2 rounded-md border border-border bg-muted/30 p-3">
            <div className="text-xs text-muted-foreground">Уже есть полный бекап? Восстановите его до создания новой учётной записи — логин, пароль и остальные настройки будут импортированы вместе.</div>
            <button type="button" disabled={busy} className="h-9 rounded-md border border-border bg-muted px-3 text-sm hover:bg-muted/80 disabled:opacity-60" onClick={() => firstRunBackupRef.current?.click()}>
              Восстановить из бекапа JSON
            </button>
            <input ref={firstRunBackupRef} type="file" accept="application/json,.json" className="hidden" onChange={(event) => { const file = event.target.files?.[0]; if (file) void restoreFirstRunBackup(file); }} />
          </div>
        )}
'''
    if error_anchor not in login:
        raise SystemExit("LoginView error anchor not found")
    login = login.replace(error_anchor, restore_ui + error_anchor, 1)

tsx = tsx[:start] + login + tsx[end:]
tsx_path.write_text(tsx)

test_path = go_path.with_name("olc_backup_test.go")
if test_path.exists():
    tests = test_path.read_text()
    if "TestBackupFirstRunImportRestoresCredentialsAndSession" not in tests:
        tests += r'''

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
		"source_host_id": backupHostID(),
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
'''
        test_path.write_text(tests)
PY

gofmt -w "$main_go"
echo "patched first-run complete backup import"
