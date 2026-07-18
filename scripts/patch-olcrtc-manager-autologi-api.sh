#!/usr/bin/env bash
# Batch 3 backend: server-side "autologi" (auto-refresh logs) setting.
#   GlobalSettings.Logs.AutoRefresh, default ON.
#   GET/PATCH /api/settings/logs -> {"auto_refresh": bool}
# When ON, the UI hides LIVE/Refresh buttons and always live-tails.
# Idempotent. Target: manager main.go. Run after golden-panel copy.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-autologi-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Extend GlobalSettings with Logs + LogsSettings type ---
gs_old = '''type GlobalSettings struct {
	Subscription *SubscriptionSettings `json:"subscription,omitempty"`
}

type SubscriptionSettings struct {
	RandomizationEnabled bool `json:"randomization_enabled"`
	RandType             int  `json:"rand_type,omitempty"` // 1=статичный хэш, 2=посекундная ротация
}'''
gs_new = '''type GlobalSettings struct {
	Subscription *SubscriptionSettings `json:"subscription,omitempty"`
	Logs         *LogsSettings         `json:"logs,omitempty"`
}

type SubscriptionSettings struct {
	RandomizationEnabled bool `json:"randomization_enabled"`
	RandType             int  `json:"rand_type,omitempty"` // 1=статичный хэш, 2=посекундная ротация
}

type LogsSettings struct {
	// AutoRefresh: when true, log views auto-tail and hide the LIVE/Refresh
	// buttons. Pointer so we can distinguish "unset" (default ON) from explicit false.
	AutoRefresh *bool `json:"auto_refresh,omitempty"`
}'''
if 'type LogsSettings struct {' in t:
    print("[patch-autologi-api] LogsSettings type already present")
elif gs_old in t:
    t = t.replace(gs_old, gs_new, 1)
    changed = True
    print("[patch-autologi-api] added LogsSettings to GlobalSettings")
else:
    print("[patch-autologi-api] WARN: GlobalSettings anchor not found")

# --- 2. Helper: autologiEnabled(cfg) defaults ON ---
if 'func autologiEnabled(' not in t:
    helper = '''
// autologiEnabled reports whether log views should auto-refresh. Defaults to
// true (ON) when unset.
func autologiEnabled(cfg Config) bool {
	if cfg.GlobalSettings == nil || cfg.GlobalSettings.Logs == nil || cfg.GlobalSettings.Logs.AutoRefresh == nil {
		return true
	}
	return *cfg.GlobalSettings.Logs.AutoRefresh
}

'''
    anchor = 'func globalRandomizationEnabled(cfg Config) bool {'
    if anchor in t:
        t = t.replace(anchor, helper + anchor, 1)
        changed = True
        print("[patch-autologi-api] added autologiEnabled helper")
    else:
        print("[patch-autologi-api] WARN: cannot place autologiEnabled")
else:
    print("[patch-autologi-api] autologiEnabled already present")

# --- 3. Handler GET/PATCH /api/settings/logs ---
if 'func autologiHandler(' not in t:
    handler = '''
func autologiHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			cfg, err := loadConfig(configPath)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			writeJSONStatus(w, http.StatusOK, map[string]any{"auto_refresh": autologiEnabled(cfg)})
			return
		}
		if r.Method != http.MethodPatch {
			w.Header().Set("Allow", "GET, PATCH")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req struct {
			AutoRefresh bool `json:"auto_refresh"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		cfg, err := loadConfig(configPath)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if cfg.GlobalSettings == nil {
			cfg.GlobalSettings = &GlobalSettings{}
		}
		if cfg.GlobalSettings.Logs == nil {
			cfg.GlobalSettings.Logs = &LogsSettings{}
		}
		v := req.AutoRefresh
		cfg.GlobalSettings.Logs.AutoRefresh = &v
		if err := saveConfig(configPath, cfg); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if globalSupervisor != nil {
			globalSupervisor.UpdateSettings(cfg)
		}
		writeJSONStatus(w, http.StatusOK, map[string]any{"auto_refresh": req.AutoRefresh})
	}
}

'''
    anchor = 'func globalRandomizationHandler(configPath string) http.HandlerFunc {'
    if anchor in t:
        t = t.replace(anchor, handler + anchor, 1)
        changed = True
        print("[patch-autologi-api] added autologiHandler")
    else:
        print("[patch-autologi-api] WARN: cannot place autologiHandler")
else:
    print("[patch-autologi-api] autologiHandler already present")

# --- 4. Register route ---
route_anchor = '\thandler.Handle("/api/settings/randomization/global", adminAuth(globalRandomizationHandler(configPath)))'
route_new = route_anchor + '\n\thandler.Handle("/api/settings/logs", adminAuth(autologiHandler(configPath)))'
if 'handler.Handle("/api/settings/logs"' in t:
    print("[patch-autologi-api] route already registered")
elif route_anchor in t:
    t = t.replace(route_anchor, route_new, 1)
    changed = True
    print("[patch-autologi-api] registered /api/settings/logs route")
else:
    print("[patch-autologi-api] WARN: route anchor not found")

if changed:
    f.write_text(t)
print("[patch-autologi-api] ok")
PY
