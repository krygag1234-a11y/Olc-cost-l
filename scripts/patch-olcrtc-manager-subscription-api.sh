#!/usr/bin/env bash
# Subscription Randomization API endpoints (Slice 2)
# Must run AFTER patch-olcrtc-manager-subscription-randomization.sh
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'randomizationEnableHandler' "$MAIN_GO" && {
  echo "[patch-subscription-api] already applied"
  exit 0
}
grep -q 'resolveClientID' "$MAIN_GO" || {
  echo "[patch-subscription-api] SKIP: resolveClientID not found (run subscription-randomization first)"
  exit 0
}

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path
import re

p = Path(sys.argv[1])
t = p.read_text()

# === 0. Add global supervisor variable ===
if 'var globalSupervisor *Supervisor' not in t:
    # Add after other global variables
    global_vars_anchor = 'var adminConfigPath string'
    if global_vars_anchor in t:
        t = t.replace(global_vars_anchor, global_vars_anchor + '\nvar globalSupervisor *Supervisor', 1)
        print("[patch-subscription-api] global supervisor variable added")

# === 0b. Workaround: Add missing bridge constants if not present ===
if 'bridgeProfilesPath' not in t:
    const_block_anchor = 'const (\n\tpanelUpdateLock  = "/var/lib/olcrtc/panel-update.lock"'
    if const_block_anchor in t:
        const_insert = '''\tpanelUpdateLock    = "/var/lib/olcrtc/panel-update.lock"
\tbridgeProfilesPath = "/var/lib/olcrtc/bridge-profiles.json"
\tbridgePoolStatusFile = "/var/lib/olcrtc/bridge-pool-status.json"
\tbridgeCronPath = "/etc/cron.d/olcrtc-bridge-pool"'''
        t = t.replace('\tpanelUpdateLock  = "/var/lib/olcrtc/panel-update.lock"', const_insert, 1)
        print("[patch-subscription-api] WORKAROUND: added missing bridge constants")

# === 0c. Assign globalSupervisor in main() ===
if 'globalSupervisor = supervisor' not in t:
    main_supervisor = '\tsupervisor := NewSupervisor(olcrtcPath, startInstance)'
    if main_supervisor in t:
        t = t.replace(main_supervisor, main_supervisor + '\n\tglobalSupervisor = supervisor', 1)
        print("[patch-subscription-api] globalSupervisor assignment added")

# === 1. Add API handler functions before subscriptionHandler ===
anchor = 'func subscriptionHandler(supervisor *Supervisor) http.Handler {'
if anchor not in t:
    print("[patch-subscription-api] subscriptionHandler not found")
    raise SystemExit(1)

api_handlers = '''
func randomizationEnableHandler(configPath string) http.HandlerFunc {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodPost {
\t\t\tw.Header().Set("Allow", http.MethodPost)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tclientID := strings.TrimPrefix(r.URL.Path, "/api/clients/")
\t\tclientID = strings.TrimSuffix(clientID, "/randomization/enable")
\t\tcfg, err := loadConfig(configPath)
\t\tif err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tfound := false
\t\tvar randomizedID string
\t\tfor i := range cfg.Clients {
\t\t\tif cfg.Clients[i].ClientID == clientID {
\t\t\t\tif cfg.Clients[i].Randomization == nil {
\t\t\t\t\tcfg.Clients[i].Randomization = &ClientRandomization{}
\t\t\t\t}
\t\t\t\tcfg.Clients[i].Randomization.Enabled = true
\t\t\t\tcfg.Clients[i].Randomization.RandomizedID = generateRandomizedID(clientID, cfg.RandomizationSecret)
\t\t\t\trandomizedID = cfg.Clients[i].Randomization.RandomizedID
\t\t\t\tfound = true
\t\t\t\tbreak
\t\t\t}
\t\t}
\t\tif !found {
\t\t\thttp.NotFound(w, r)
\t\t\treturn
\t\t}
\t\tif err := saveConfig(configPath, cfg); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tif globalSupervisor != nil {
\t\t\tglobalSupervisor.UpdateSettings(cfg)
\t\t}
\t\twriteJSONStatus(w, http.StatusOK, map[string]any{"enabled": true, "randomized_id": randomizedID})
\t}
}

func randomizationDisableHandler(configPath string) http.HandlerFunc {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodPost {
\t\t\tw.Header().Set("Allow", http.MethodPost)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tclientID := strings.TrimPrefix(r.URL.Path, "/api/clients/")
\t\tclientID = strings.TrimSuffix(clientID, "/randomization/disable")
\t\tcfg, err := loadConfig(configPath)
\t\tif err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tfound := false
\t\tfor i := range cfg.Clients {
\t\t\tif cfg.Clients[i].ClientID == clientID {
\t\t\t\tif cfg.Clients[i].Randomization != nil {
\t\t\t\t\tcfg.Clients[i].Randomization.Enabled = false
\t\t\t\t}
\t\t\t\tfound = true
\t\t\t\tbreak
\t\t\t}
\t\t}
\t\tif !found {
\t\t\thttp.NotFound(w, r)
\t\t\treturn
\t\t}
\t\tif err := saveConfig(configPath, cfg); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tif globalSupervisor != nil {
\t\t\tglobalSupervisor.UpdateSettings(cfg)
\t\t}
\t\twriteJSONStatus(w, http.StatusOK, map[string]any{"enabled": false})
\t}
}

func randomizationRegenerateHandler(configPath string) http.HandlerFunc {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodPost {
\t\t\tw.Header().Set("Allow", http.MethodPost)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tclientID := strings.TrimPrefix(r.URL.Path, "/api/clients/")
\t\tclientID = strings.TrimSuffix(clientID, "/randomization/regenerate")
\t\tcfg, err := loadConfig(configPath)
\t\tif err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tfound := false
\t\tvar randomizedID string
\t\tfor i := range cfg.Clients {
\t\t\tif cfg.Clients[i].ClientID == clientID {
\t\t\t\tif cfg.Clients[i].Randomization == nil {
\t\t\t\t\tcfg.Clients[i].Randomization = &ClientRandomization{Enabled: true}
\t\t\t\t}
\t\t\t\tcfg.Clients[i].Randomization.RandomizedID = generateRandomizedID(clientID, cfg.RandomizationSecret)
\t\t\t\trandomizedID = cfg.Clients[i].Randomization.RandomizedID
\t\t\t\tfound = true
\t\t\t\tbreak
\t\t\t}
\t\t}
\t\tif !found {
\t\t\thttp.NotFound(w, r)
\t\t\treturn
\t\t}
\t\tif err := saveConfig(configPath, cfg); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tif globalSupervisor != nil {
\t\t\tglobalSupervisor.UpdateSettings(cfg)
\t\t}
\t\twriteJSONStatus(w, http.StatusOK, map[string]any{"randomized_id": randomizedID})
\t}
}

func subscriptionURLHandler(configPath string) http.HandlerFunc {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodGet {
\t\t\tw.Header().Set("Allow", http.MethodGet)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tclientID := strings.TrimPrefix(r.URL.Path, "/api/clients/")
\t\tclientID = strings.TrimSuffix(clientID, "/subscription-url")
\t\tcfg, err := loadConfig(configPath)
\t\tif err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tvar client *Client
\t\tfor i := range cfg.Clients {
\t\t\tif cfg.Clients[i].ClientID == clientID {
\t\t\t\tclient = &cfg.Clients[i]
\t\t\t\tbreak
\t\t\t}
\t\t}
\t\tif client == nil {
\t\t\thttp.NotFound(w, r)
\t\t\treturn
\t\t}
\t\tsubPath := cfg.SubscriptionPath
\t\tif subPath == "" {
\t\t\tsubPath = "sub"
\t\t}
\t\tuseRandomized := false
\t\trandomizedID := ""
\t\tif client.Randomization != nil && client.Randomization.Enabled && client.Randomization.RandomizedID != "" {
\t\t\tuseRandomized = true
\t\t\trandomizedID = client.Randomization.RandomizedID
\t\t}
\t\tif globalRandomizationEnabled(cfg) && client.Randomization != nil && client.Randomization.RandomizedID != "" {
\t\t\tuseRandomized = true
\t\t\trandomizedID = client.Randomization.RandomizedID
\t\t}
\t\tvar subURL string
\t\tif useRandomized {
\t\t\tsubURL = fmt.Sprintf("/%s/%s", subPath, randomizedID)
\t\t} else {
\t\t\tsubURL = fmt.Sprintf("/%s/%s", subPath, clientID)
\t\t}
\t\tif globalSupervisor != nil {
\t\t\tglobalSupervisor.UpdateSettings(cfg)
\t\t}
\t\twriteJSONStatus(w, http.StatusOK, map[string]any{"url": subURL})
\t}
}

func globalRandomizationHandler(configPath string) http.HandlerFunc {
\treturn func(w http.ResponseWriter, r *http.Request) {
\t\tif r.Method != http.MethodPatch {
\t\t\tw.Header().Set("Allow", http.MethodPatch)
\t\t\thttp.Error(w, "method not allowed", http.StatusMethodNotAllowed)
\t\t\treturn
\t\t}
\t\tvar req struct {
\t\t\tEnabled bool `json:"enabled"`
\t\t}
\t\tif err := json.NewDecoder(r.Body).Decode(&req); err != nil {
\t\t\thttp.Error(w, "invalid request", http.StatusBadRequest)
\t\t\treturn
\t\t}
\t\tcfg, err := loadConfig(configPath)
\t\tif err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tif cfg.GlobalSettings == nil {
\t\t\tcfg.GlobalSettings = &GlobalSettings{}
\t\t}
\t\tif cfg.GlobalSettings.Subscription == nil {
\t\t\tcfg.GlobalSettings.Subscription = &SubscriptionSettings{}
\t\t}
\t\tcfg.GlobalSettings.Subscription.RandomizationEnabled = req.Enabled
\t\tif err := saveConfig(configPath, cfg); err != nil {
\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)
\t\t\treturn
\t\t}
\t\tif globalSupervisor != nil {
\t\t\tglobalSupervisor.UpdateSettings(cfg)
\t\t}
\t\twriteJSONStatus(w, http.StatusOK, map[string]any{"enabled": req.Enabled})
\t}
}

'''

t = t.replace(anchor, api_handlers + anchor, 1)
print("[patch-subscription-api] handler functions added")

# === 2. Modify existing /api/clients/ handler to route randomization paths ===
# Insert routing BEFORE method check, using r.URL.Path directly (not rest)
clients_handler_anchor = '\thandler.Handle("/api/clients/", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {'
if clients_handler_anchor in t and 'urlPath := r.URL.Path' not in t:
    # Find position after the opening line
    idx = t.index(clients_handler_anchor)
    insert_pos = t.index('\n', idx) + 1
    routing_block = '''\t\t// Subscription randomization API routes (before method check)
\t\turlPath := r.URL.Path
\t\tif strings.HasSuffix(urlPath, "/randomization/enable") {
\t\t\trandomizationEnableHandler(configPath)(w, r)
\t\t\treturn
\t\t}
\t\tif strings.HasSuffix(urlPath, "/randomization/disable") {
\t\t\trandomizationDisableHandler(configPath)(w, r)
\t\t\treturn
\t\t}
\t\tif strings.HasSuffix(urlPath, "/randomization/regenerate") {
\t\t\trandomizationRegenerateHandler(configPath)(w, r)
\t\t\treturn
\t\t}
\t\tif strings.HasSuffix(urlPath, "/subscription-url") {
\t\t\tsubscriptionURLHandler(configPath)(w, r)
\t\t\treturn
\t\t}
'''
    t = t[:insert_pos] + routing_block + t[insert_pos:]
    print("[patch-subscription-api] /api/clients/ routing added before method check")
else:
    if 'urlPath := r.URL.Path' in t:
        print("[patch-subscription-api] routing already present")
    else:
        print("[patch-subscription-api] ERROR: /api/clients/ handler not found")
        raise SystemExit(1)

# === 3. Add /api/settings/randomization/global route before /api/settings/ handler ===
settings_handler = 'handler.Handle("/api/settings/", adminAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {'
if settings_handler in t and 'globalRandomizationHandler' not in t:
    global_route = '\thandler.Handle("/api/settings/randomization/global", adminAuth(globalRandomizationHandler(configPath)))\n\t'
    t = t.replace(settings_handler, global_route + settings_handler, 1)
    print("[patch-subscription-api] /api/settings/randomization/global route added")

p.write_text(t)
print("[patch-subscription-api] ok")
PY
