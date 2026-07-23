#!/usr/bin/env bash
# Olc-cost-l backend: СКОУП рандомизации — к чему применяется рандомизация:
# "both" (client_id + крипто-ключи, дефолт) | "client_id" | "crypto". Хранится в
# GlobalSettings.Subscription.RandScope. GET /api/settings/randomization/global
# ТЕПЕРЬ отдаёт rand_scope (read-only, дефолт both). Отдельный эндпоинт
# GET/PATCH /api/settings/randomization/scope {rand_scope} — задаёт скоуп НЕЗАВИСИМО
# от enable/type. Скоуп гейтит «+»/предупреждения по секциям (🎫=client_id, 🔌=крипто)
# и (в будущем) вывод alt-ключей. Idempotent. Target: manager cmd/olcrtc-manager/main.go.
# Run ПОСЛЕ subscription-randomization (нужна SubscriptionSettings) и subscription-api.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-rand-scope-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# 1. Поле RandScope в SubscriptionSettings
if 'rand_scope,omitempty' not in t:
    anchor = '''	RandomizationEnabled bool `json:"randomization_enabled"`
	RandType             int  `json:"rand_type,omitempty"` // 1=статичный хэш, 2=посекундная ротация
}'''
    repl = '''	RandomizationEnabled bool `json:"randomization_enabled"`
	RandType             int  `json:"rand_type,omitempty"` // 1=статичный хэш, 2=посекундная ротация
	RandScope            string `json:"rand_scope,omitempty"` // both|client_id|crypto (дефолт both)
}'''
    if anchor in t:
        t = t.replace(anchor, repl, 1); changed = True
        print("[patch-rand-scope-api] RandScope field: ok")
    else:
        print("[patch-rand-scope-api] WARN: SubscriptionSettings anchor not found")
else:
    print("[patch-rand-scope-api] RandScope field: already applied")

# 2. Хелпер olcRandScope + маршрут (перед globalRandomizationHandler)
if 'func olcRandScope(' not in t:
    anchor = 'func globalRandomizationHandler(configPath string) http.HandlerFunc {'
    block = '''// olcRandScope — текущий скоуп рандомизации: both|client_id|crypto (дефолт both).
func olcRandScope(cfg Config) string {
	if cfg.GlobalSettings != nil && cfg.GlobalSettings.Subscription != nil {
		s := strings.TrimSpace(cfg.GlobalSettings.Subscription.RandScope)
		if s == "client_id" || s == "crypto" {
			return s
		}
	}
	return "both"
}

// randomizationScopeHandler — GET/PATCH скоупа рандомизации НЕЗАВИСИМО от enable/type.
func randomizationScopeHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			cfg, err := loadConfig(configPath)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			writeJSONStatus(w, http.StatusOK, map[string]any{"rand_scope": olcRandScope(cfg)})
			return
		}
		if r.Method != http.MethodPatch && r.Method != http.MethodPut && r.Method != http.MethodPost {
			w.Header().Set("Allow", "GET, PATCH")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			RandScope string `json:"rand_scope"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		sc := strings.TrimSpace(req.RandScope)
		if sc != "client_id" && sc != "crypto" {
			sc = "both"
		}
		cfg, err := loadConfig(configPath)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if cfg.GlobalSettings == nil {
			cfg.GlobalSettings = &GlobalSettings{}
		}
		if cfg.GlobalSettings.Subscription == nil {
			cfg.GlobalSettings.Subscription = &SubscriptionSettings{}
		}
		cfg.GlobalSettings.Subscription.RandScope = sc
		if err := saveConfig(configPath, cfg); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSONStatus(w, http.StatusOK, map[string]any{"rand_scope": sc})
	}
}

'''
    if anchor in t:
        t = t.replace(anchor, block + anchor, 1); changed = True
        print("[patch-rand-scope-api] helper+handler: ok")
    else:
        print("[patch-rand-scope-api] WARN: globalRandomizationHandler anchor not found")
else:
    print("[patch-rand-scope-api] helper+handler: already applied")

# 3. Роут /api/settings/randomization/scope
if '/api/settings/randomization/scope' not in t:
    anchor = '\thandler.Handle("/api/settings/randomization/global", adminAuth(globalRandomizationHandler(configPath)))'
    add = anchor + '''
	handler.Handle("/api/settings/randomization/scope", adminAuth(randomizationScopeHandler(configPath)))'''
    if anchor in t:
        t = t.replace(anchor, add, 1); changed = True
        print("[patch-rand-scope-api] route: ok")
    else:
        print("[patch-rand-scope-api] WARN: randomization/global route anchor not found")
else:
    print("[patch-rand-scope-api] route: already applied")

# 4. /global GET += rand_scope (read-only отражение)
old_get = 'writeJSONStatus(w, http.StatusOK, map[string]any{"enabled": globalRandomizationEnabled(cfg), "rand_type": gt})'
new_get = 'writeJSONStatus(w, http.StatusOK, map[string]any{"enabled": globalRandomizationEnabled(cfg), "rand_type": gt, "rand_scope": olcRandScope(cfg)})'
if new_get in t:
    print("[patch-rand-scope-api] /global GET rand_scope: already applied")
elif old_get in t:
    t = t.replace(old_get, new_get, 1); changed = True
    print("[patch-rand-scope-api] /global GET rand_scope: ok")
else:
    print("[patch-rand-scope-api] WARN: /global GET anchor not found")

if changed:
    f.write_text(t)
    print("[patch-rand-scope-api] OK: main.go updated")
else:
    print("[patch-rand-scope-api] no changes (idempotent)")
PY
