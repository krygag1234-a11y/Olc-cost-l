#!/usr/bin/env bash
# Olc-cost-l backend: Backup / Restore API (экспорт-импорт ВСЕХ данных панели).
#
#   GET  /api/backup/export  -> скачать версионированный JSON со ВСЕМИ данными
#                               (config.json + panel.env + features.env +
#                               deploy-profile + notification-settings +
#                               instance-defaults).
#   POST /api/backup/import  <- принять такой JSON и восстановить данные
#                               (schema-независимо: сырой config + deep-merge).
#
# УСТОЙЧИВОСТЬ К ВЕРСИЯМ: бэкап хранит СЫРОЙ JSON (не через Go-struct, поля не
# теряются), а импорт делает ПОКЛЮЧЕВОЙ deep-merge (данные бэкапа поверх текущих
# дефолтов). Стабильные идентификаторы = сами ключи JSON. Хук migrateBackup()
# для будущих переименований ключей.
#
# ВАЖНО ДЛЯ БУДУЩИХ АГЕНТОВ/РАЗРАБОТЧИКОВ: если добавляете НОВУЮ настройку,
# состояние или файл, который должен переживать переустановку/перенос на новый
# VPS — убедитесь, что он лежит в config.json ИЛИ в одном из файлов из
# backupExtraFiles(); при переименовании ключа добавьте миграцию в migrateBackup().
# Иначе новые данные НЕ попадут в экспорт/импорт. См. docs/BACKUP.md.
#
# Idempotent. Target: manager main.go. Run after golden-panel copy.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-backup-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Регистрация роутов (после /api/instance-defaults — стабильный якорь) ---
route_anchor = '\thandler.Handle("/api/instance-defaults", adminAuth(http.HandlerFunc(instanceDefaultsHandler)))'
route_add = route_anchor + '''
	// Olc-cost-l: экспорт/импорт всех данных панели (бэкап). Данные — только у
	// пользователя, локально. Устойчиво к смене версий (сырой JSON + deep-merge).
	handler.Handle("/api/backup/export", adminAuth(http.HandlerFunc(backupExportHandler(configPath))))
	handler.Handle("/api/backup/import", adminAuth(http.HandlerFunc(backupImportHandler(configPath))))'''
if '/api/backup/export' in t:
    print("[patch-backup-api] routes already present")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1)
    changed = True
    print("[patch-backup-api] registered /api/backup/{export,import}")
else:
    print("[patch-backup-api] WARN: route anchor (/api/instance-defaults) not found — skip routes")

# --- 2. Определения обработчиков (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// ============================================================================
// Olc-cost-l: Backup / Restore — экспорт-импорт ВСЕХ данных панели.
//
// Устойчивость к версиям: экспорт хранит СЫРОЙ config.json (generic JSON, поля
// не теряются) + сопутствующие файлы; импорт делает ПОКЛЮЧЕВОЙ deep-merge
// (значения бэкапа поверх текущих дефолтов). Стабильные идентификаторы = ключи
// JSON. Все данные — только у пользователя, хранятся локально.
//
// !!! ПРИ ИЗМЕНЕНИИ UI/НАСТРОЕК: если добавляете настройку/состояние/файл,
// который должен переживать переустановку — он ДОЛЖЕН попасть в config.json или
// в backupExtraFiles() ниже; при переименовании ключа — миграция в migrateBackup().
// ============================================================================

const olcBackupSchemaVersion = 1

// backupExtraFiles: файлы настроек/состояния (кроме config.json), входящие в
// бэкап. Ключ — стабильный ид в конверте бэкапа, значение — путь на диске.
// ДОБАВЛЯЙТЕ СЮДА новые файлы настроек, которые должны переживать перенос.
func backupExtraFiles(configPath string) map[string]string {
	dir := filepath.Dir(configPath)
	return map[string]string{
		"panel_env":             filepath.Join(dir, "panel.env"),
		"features_env":          filepath.Join(dir, "features.env"),
		"deploy_profile":        filepath.Join(dir, "deploy-profile.json"),
		"notification_settings": notificationSettingsPath,
		"instance_defaults":     instanceDefaultsPath,
		"access_control":        "/var/lib/olcrtc/access-control.json",
		"split_discovered":      "/var/lib/olcrtc/lists/panel-carrier-discovered.json",
	}
}

// deepMergeJSON: значения src (бэкап) поверх dst (текущее). Вложенные объекты
// сливаются по ключам; массивы и скаляры src ЗАМЕНЯЮТ dst целиком (список
// клиентов/локаций/инстансов восстанавливается как есть). Схемо-независимо.
func deepMergeJSON(dst, src map[string]any) map[string]any {
	if dst == nil {
		dst = map[string]any{}
	}
	for k, sv := range src {
		if sm, ok := sv.(map[string]any); ok {
			if dm, ok := dst[k].(map[string]any); ok {
				dst[k] = deepMergeJSON(dm, sm)
				continue
			}
		}
		dst[k] = sv
	}
	return dst
}

// mergeEnvFile: обновляет KEY= строки значениями kv, сохраняя прочие строки и
// комментарии; недостающие ключи дописывает. Возвращает nil при успехе.
func mergeEnvFile(path string, kv map[string]string) error {
	var lines []string
	if data, err := os.ReadFile(path); err == nil {
		lines = strings.Split(string(data), "\n")
	}
	seen := map[string]bool{}
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") || !strings.Contains(trimmed, "=") {
			continue
		}
		key := strings.TrimSpace(strings.SplitN(trimmed, "=", 2)[0])
		if val, ok := kv[key]; ok {
			lines[i] = key + "=\"" + val + "\""
			seen[key] = true
		}
	}
	var missing []string
	for k := range kv {
		if !seen[k] {
			missing = append(missing, k)
		}
	}
	sort.Strings(missing)
	for _, k := range missing {
		lines = append(lines, k+"=\""+kv[k]+"\"")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o600)
}

// migrateBackup: хук миграции старых бэкапов на текущую схему.
// ПРИ ПЕРЕИМЕНОВАНИИ/ПЕРЕЕЗДЕ ключей настроек добавляйте преобразование здесь,
// сверяясь с версией sv (например: if sv < 2 { ...перенос старого ключа... }).
func migrateBackup(sv int, env map[string]any) map[string]any {
	// schema_version 1 — базовая. Будущие версии добавляют шаги ниже.
	return env
}

func backupExportHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
			return
		}
		env := map[string]any{
			"olc_backup":     true,
			"schema_version": olcBackupSchemaVersion,
			"app":            "olcrtc-manager",
			"created_at":     time.Now().UTC().Format(time.RFC3339),
			"note":           "Эти данные принадлежат только вам и хранятся локально на устройстве с панелью. Сервер их никуда не отправляет.",
		}
		// config.json — сырой generic JSON (поля не теряются между версиями)
		if raw, err := os.ReadFile(configPath); err == nil {
			var cfg any
			if json.Unmarshal(raw, &cfg) == nil {
				env["config"] = cfg
			}
		}
		extras := map[string]any{}
		for key, path := range backupExtraFiles(configPath) {
			data, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			if strings.HasSuffix(path, ".json") {
				var v any
				if json.Unmarshal(data, &v) == nil {
					extras[key] = map[string]any{"kind": "json", "value": v}
				}
			} else {
				kv, _ := readEnvFile(path)
				vals := map[string]any{}
				for k, val := range kv {
					vals[k] = val
				}
				extras[key] = map[string]any{"kind": "env", "values": vals}
			}
		}
		env["extras"] = extras
		manifest := []string{"config"}
		for k := range extras {
			manifest = append(manifest, k)
		}
		sort.Strings(manifest)
		env["manifest"] = manifest

		fname := "olc-backup-" + time.Now().UTC().Format("20060102-150405") + ".json"
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Content-Disposition", "attachment; filename=\""+fname+"\"")
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		_ = enc.Encode(env)
		appendAudit(configPath, "backup_export", strings.Join(manifest, ","))
	}
}

func backupImportHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
			return
		}
		body, err := io.ReadAll(io.LimitReader(r.Body, 64<<20)) // 64 MiB (много инстансов/значений)
		if err != nil {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "read body: " + err.Error()})
			return
		}
		var env map[string]any
		if err := json.Unmarshal(body, &env); err != nil {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "неверный JSON бэкапа: " + err.Error()})
			return
		}
		if v, _ := env["olc_backup"].(bool); !v {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "это не файл бэкапа Olc-cost-l (нет поля olc_backup)"})
			return
		}
		sv := 0
		if fv, ok := env["schema_version"].(float64); ok {
			sv = int(fv)
		}
		if sv > olcBackupSchemaVersion {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": fmt.Sprintf("бэкап новее панели (schema_version=%d > %d) — обновите панель", sv, olcBackupSchemaVersion)})
			return
		}
		env = migrateBackup(sv, env)

		restored := []string{}
		// config.json — deep-merge поверх текущего (данные бэкапа выигрывают, новые
		// дефолты новой версии сохраняются). Снимок текущего — в backups/.
		if bc, ok := env["config"].(map[string]any); ok {
			cur := map[string]any{}
			if raw, err := os.ReadFile(configPath); err == nil {
				_ = json.Unmarshal(raw, &cur)
			}
			merged := deepMergeJSON(cur, bc)
			if out, err := json.MarshalIndent(merged, "", "  "); err == nil {
				backupConfig(configPath)
				tmp := configPath + ".tmp"
				if os.WriteFile(tmp, append(out, '\n'), 0o600) == nil && os.Rename(tmp, configPath) == nil {
					restored = append(restored, "config")
				}
			}
		}
		if extras, ok := env["extras"].(map[string]any); ok {
			for key, path := range backupExtraFiles(configPath) {
				ev, ok := extras[key].(map[string]any)
				if !ok {
					continue
				}
				switch kind, _ := ev["kind"].(string); kind {
				case "json":
					bv, ok := ev["value"].(map[string]any)
					if !ok {
						continue
					}
					cur := map[string]any{}
					if raw, err := os.ReadFile(path); err == nil {
						_ = json.Unmarshal(raw, &cur)
					}
					merged := deepMergeJSON(cur, bv)
					if out, err := json.MarshalIndent(merged, "", "  "); err == nil {
						_ = os.MkdirAll(filepath.Dir(path), 0o755)
						if os.WriteFile(path, append(out, '\n'), 0o644) == nil {
							restored = append(restored, key)
						}
					}
				case "env":
					vals, ok := ev["values"].(map[string]any)
					if !ok {
						continue
					}
					kv := map[string]string{}
					for k, v := range vals {
						kv[k] = fmt.Sprintf("%v", v)
					}
					if mergeEnvFile(path, kv) == nil {
						restored = append(restored, key)
					}
				}
			}
		}
		sort.Strings(restored)
		appendAudit(configPath, "backup_import", strings.Join(restored, ","))
		writeJSON(w, map[string]any{
			"status":   "ok",
			"restored": restored,
			"note":     "Данные восстановлены. Перезапустите панель, чтобы применить (Настройки → Перезапуск), или переустановите/запустите панель на новом VPS.",
		})
	}
}

'''
if 'func backupExportHandler(' in t:
    print("[patch-backup-api] handlers already present")
elif fn_anchor in t:
    t = t.replace(fn_anchor, fn_block + fn_anchor, 1)
    changed = True
    print("[patch-backup-api] added backup handlers + helpers")
else:
    print("[patch-backup-api] WARN: writeJSON anchor not found — skip handlers")

if changed:
    f.write_text(t)
    print("[patch-backup-api] OK: main.go updated")
else:
    print("[patch-backup-api] no changes (idempotent)")
PY
