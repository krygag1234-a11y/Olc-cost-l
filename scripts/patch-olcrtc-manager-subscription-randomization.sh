#!/usr/bin/env bash
# Subscription Randomization: защита от enumeration через HMAC-SHA256 hash client_id
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'ClientRandomization' "$MAIN_GO" && {
  echo "[patch-subscription-randomization] already applied"
  exit 0
}

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path
import re

p = Path(sys.argv[1])
t = p.read_text()

# === 1. Add imports (crypto/hmac, crypto/sha256) ===
imports_section = re.search(r'import \((.*?)\)', t, re.DOTALL)
if imports_section and 'crypto/hmac' not in t:
    old_imports = imports_section.group(0)
    # Add after crypto/rand
    new_imports = old_imports.replace(
        '"crypto/rand"',
        '"crypto/hmac"\n\t"crypto/rand"\n\t"crypto/sha256"'
    )
    t = t.replace(old_imports, new_imports, 1)
    print("[patch-randomization] imports added")

# === 2. Add structs after Client struct ===
client_struct_end = 'type Quota struct {'
if client_struct_end in t and 'type ClientRandomization struct' not in t:
    structs = '''
type ClientRandomization struct {
\tEnabled      bool   `json:"enabled"`
\tRandType     int    `json:"rand_type,omitempty"` // 1=статичный хэш, 2=посекундная ротация
\tRandomizedID string `json:"randomized_id,omitempty"`
}

type GlobalSettings struct {
\tSubscription *SubscriptionSettings `json:"subscription,omitempty"`
}

type SubscriptionSettings struct {
\tRandomizationEnabled bool `json:"randomization_enabled"`
\tRandType             int  `json:"rand_type,omitempty"` // 1=статичный хэш, 2=посекундная ротация
}

'''
    t = t.replace(client_struct_end, structs + client_struct_end, 1)
    print("[patch-randomization] structs added")

# === 3. Modify Client struct ===
client_def = re.search(r'type Client struct \{[^}]+\}', t, re.DOTALL)
if client_def and 'Randomization' not in client_def.group(0):
    old_client = client_def.group(0)
    # Add before closing brace
    new_client = old_client.replace(
        '\tLocations []Location `json:"locations"`',
        '\tLocations     []Location            `json:"locations"`\n\tRandomization *ClientRandomization  `json:"randomization,omitempty"`'
    )
    t = t.replace(old_client, new_client, 1)
    print("[patch-randomization] Client struct modified")

# === 4. Modify Config struct ===
config_def = re.search(r'type Config struct \{.*?Locations\s+\[\]Location[^}]+\}', t, re.DOTALL)
if config_def and 'RandomizationSecret' not in config_def.group(0):
    old_config = config_def.group(0)
    new_config = old_config.replace(
        '\tLocations        []Location `json:"locations"`',
        '\tLocations           []Location       `json:"locations"`\n\tGlobalSettings      *GlobalSettings  `json:"global_settings,omitempty"`\n\tRandomizationSecret string           `json:"randomization_secret,omitempty"`'
    )
    t = t.replace(old_config, new_config, 1)
    print("[patch-randomization] Config struct modified")

# === 5. Modify Normalize() to call initRandomizationSecret() ===
normalize_func = re.search(r'func \(c \*Config\) Normalize\(\) \{.*?\n\tc\.Locations = locations\n\}', t, re.DOTALL)
if normalize_func and 'initRandomizationSecret' not in normalize_func.group(0):
    old_normalize = normalize_func.group(0)
    new_normalize = old_normalize.replace(
        '\tc.Locations = locations\n}',
        '\tc.Locations = locations\n\n\tc.initRandomizationSecret()\n}'
    )
    t = t.replace(old_normalize, new_normalize, 1)
    print("[patch-randomization] Normalize() modified")

# === 6. Add helper functions after Normalize() ===
if 'func (c *Config) initRandomizationSecret()' not in t:
    anchor = 'func (c Config) Validate() error {'
    if anchor in t:
        helpers = '''
func (c *Config) initRandomizationSecret() {
\tif c.RandomizationSecret != "" {
\t\treturn
\t}

\tbuf := make([]byte, 32)
\tif _, err := rand.Read(buf); err != nil {
\t\tlog.Printf("WARN: failed to generate randomization secret: %v", err)
\t\treturn
\t}
\tc.RandomizationSecret = hex.EncodeToString(buf)
}

func generateRandomizedID(clientID, secret string) string {
\tif secret == "" {
\t\treturn ""
\t}

\tdata := fmt.Sprintf("%s:%d", clientID, time.Now().UnixNano())
\th := hmac.New(sha256.New, []byte(secret))
\th.Write([]byte(data))
\thash := hex.EncodeToString(h.Sum(nil))

\tif len(hash) > 16 {
\t\treturn hash[:16]
\t}
\treturn hash
}

// rotatingHashAt — тип 2: HMAC(secret, clientID@sec)[:16] для конкретной секунды.
func rotatingHashAt(clientID, secret string, sec int64) string {
\tif secret == "" {
\t\treturn ""
\t}
\tdata := fmt.Sprintf("%s@%d", clientID, sec)
\th := hmac.New(sha256.New, []byte(secret))
\th.Write([]byte(data))
\thash := hex.EncodeToString(h.Sum(nil))
\tif len(hash) > 16 {
\t\treturn hash[:16]
\t}
\treturn hash
}

// rotatingHashMatches — окно приёма: текущая И предыдущая секунда.
func rotatingHashMatches(clientID, secret, candidate string) bool {
\tif candidate == "" || secret == "" {
\t\treturn false
\t}
\tnow := time.Now().Unix()
\tif hmac.Equal([]byte(candidate), []byte(rotatingHashAt(clientID, secret, now))) {
\t\treturn true
\t}
\treturn hmac.Equal([]byte(candidate), []byte(rotatingHashAt(clientID, secret, now-1)))
}

func globalRandomizationEnabled(cfg Config) bool {
\tif cfg.GlobalSettings == nil || cfg.GlobalSettings.Subscription == nil {
\t\treturn false
\t}
\treturn cfg.GlobalSettings.Subscription.RandomizationEnabled
}

// randTypeFor — эффективный тип рандомизации для клиента (0=выкл, 1=статичный, 2=ротация).
// Глобальная рандомизация имеет приоритет над per-client (зеркало гейтинга UI).
func randTypeFor(client Client, cfg Config) int {
\tif globalRandomizationEnabled(cfg) {
\t\tif cfg.GlobalSettings != nil && cfg.GlobalSettings.Subscription != nil && cfg.GlobalSettings.Subscription.RandType > 0 {
\t\t\treturn cfg.GlobalSettings.Subscription.RandType
\t\t}
\t\treturn 1
\t}
\tif client.Randomization != nil && client.Randomization.Enabled {
\t\tif client.Randomization.RandType > 0 {
\t\t\treturn client.Randomization.RandType
\t\t}
\t\treturn 1
\t}
\treturn 0
}

func resolveClientID(requestedID string, cfg Config) (string, error) {
\t// 1. requested == оригинальный client_id.
\tfor _, client := range cfg.Clients {
\t\tif client.ClientID == requestedID {
\t\t\tswitch randTypeFor(client, cfg) {
\t\t\tcase 0:
\t\t\t\treturn requestedID, nil // рандомизация выкл — обычный доступ
\t\t\tcase 2:
\t\t\t\t// тип 2: оригинальный id проходит шлюз; доступ ограничивает
\t\t\t\t// контроль доступа по устройству (bypass для разрешённых).
\t\t\t\treturn requestedID, nil
\t\t\tdefault:
\t\t\t\t// тип 1: оригинальный id заблокирован, работает только статичный хэш.
\t\t\t\treturn "", errors.New("not found")
\t\t\t}
\t\t}
\t}

\t// 2. requested == статичный RandomizedID (тип 1).
\tfor _, client := range cfg.Clients {
\t\tif requestedID != "" && client.Randomization != nil && client.Randomization.RandomizedID == requestedID {
\t\t\tif randTypeFor(client, cfg) != 0 {
\t\t\t\treturn client.ClientID, nil
\t\t\t}
\t\t\treturn "", errors.New("not found")
\t\t}
\t}

\t// 3. requested == ротирующийся хэш (тип 2, окно текущая/предыдущая секунда).
\tfor _, client := range cfg.Clients {
\t\tif randTypeFor(client, cfg) == 2 && rotatingHashMatches(client.ClientID, cfg.RandomizationSecret, requestedID) {
\t\t\treturn client.ClientID, nil
\t\t}
\t}

\treturn "", errors.New("not found")
}

'''
        t = t.replace(anchor, helpers + anchor, 1)
        print("[patch-randomization] helper functions added")

# === 7. Modify subscriptionHandler to use resolveClientID ===
sub_handler = re.search(r'func subscriptionHandler\(supervisor \*Supervisor\) http\.Handler \{.*?^\}', t, re.DOTALL | re.MULTILINE)
if sub_handler and 'resolveClientID' not in sub_handler.group(0):
    old_handler = sub_handler.group(0)
    new_handler = '''func subscriptionHandler(supervisor *Supervisor) http.Handler {
\treturn http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
\t\trequestedID, ok := clientIDFromSubscriptionPath(r.URL.Path, supervisor.SubscriptionPath())
\t\tif !ok {
\t\t\thttp.NotFound(w, r)
\t\t\treturn
\t\t}

\t\tsupervisor.mu.RLock()
\t\tcfg := supervisor.cfg
\t\tsupervisor.mu.RUnlock()

\t\tresolvedClientID, err := resolveClientID(requestedID, cfg)
\t\tif err != nil {
\t\t\thttp.NotFound(w, r)
\t\t\treturn
\t\t}

\t\tsub, ok := supervisor.SubscriptionForClient(resolvedClientID, time.Now())
\t\tif !ok {
\t\t\thttp.NotFound(w, r)
\t\t\treturn
\t\t}

\t\tw.Header().Set("Content-Type", "text/plain; charset=utf-8")
\t\t_, _ = w.Write([]byte(sub))
\t})
}'''
    t = t.replace(old_handler, new_handler, 1)
    print("[patch-randomization] subscriptionHandler modified")

# === 8. Modify loadConfig to auto-save secret ===
load_config = re.search(r'func loadConfig\(path string\) \(Config, error\) \{.*?return cfg, nil\n\}', t, re.DOTALL)
if load_config and 'secretWasEmpty' not in load_config.group(0):
    old_load = load_config.group(0)
    new_load = old_load.replace(
        '\tvar cfg Config\n\tif err := json.Unmarshal(data, &cfg); err != nil {\n\t\treturn Config{}, fmt.Errorf("parse config: %w", err)\n\t}\n\tcfg.Normalize()',
        '\tvar cfg Config\n\tif err := json.Unmarshal(data, &cfg); err != nil {\n\t\treturn Config{}, fmt.Errorf("parse config: %w", err)\n\t}\n\n\tsecretWasEmpty := cfg.RandomizationSecret == ""\n\tcfg.Normalize()'
    )
    new_load = new_load.replace(
        '\tif warns := sanitizeConfigInvalidLocations(&cfg); len(warns) > 0 {\n\t\tfor _, w := range warns {\n\t\t\tlog.Printf("config sanitize: %s", w)\n\t\t}\n\t\t_ = saveConfig(path, cfg)\n\t}\n\treturn cfg, nil',
        '\tneedsSave := false\n\tif warns := sanitizeConfigInvalidLocations(&cfg); len(warns) > 0 {\n\t\tfor _, w := range warns {\n\t\t\tlog.Printf("config sanitize: %s", w)\n\t\t}\n\t\tneedsSave = true\n\t}\n\tif secretWasEmpty && cfg.RandomizationSecret != "" {\n\t\tneedsSave = true\n\t}\n\n\tif needsSave {\n\t\t_ = saveConfig(path, cfg)\n\t}\n\treturn cfg, nil'
    )
    t = t.replace(old_load, new_load, 1)
    print("[patch-randomization] loadConfig modified")

# === 9. Expose randomization in /api/state ClientState ===
# 9a. Add Randomization field to ClientState struct
client_state_struct = '''type ClientState struct {
	ClientID  string          `json:"client_id"`
	Refresh   string          `json:"refresh,omitempty"`
	Quota     Quota           `json:"quota"`
	Locations []LocationState `json:"locations"`
}'''
if client_state_struct in t and 'Randomization *ClientRandomization `json:"randomization' not in t:
    client_state_new = '''type ClientState struct {
	ClientID      string               `json:"client_id"`
	Refresh       string               `json:"refresh,omitempty"`
	Quota         Quota                `json:"quota"`
	Locations     []LocationState      `json:"locations"`
	Randomization *ClientRandomization `json:"randomization,omitempty"`
}'''
    t = t.replace(client_state_struct, client_state_new, 1)
    print("[patch-randomization] ClientState struct extended with Randomization")

# 9b. Capture randomization pointer in State() lookup loop and emit it
state_lookup = '''		quota := Quota{}
		refresh := ""
		for _, client := range s.cfg.Clients {
			if client.ClientID == id {
				quota = client.Quota
				refresh = client.Refresh
				break
			}
		}'''
if state_lookup in t and 'var randomization *ClientRandomization' not in t:
    state_lookup_new = '''		quota := Quota{}
		refresh := ""
		var randomization *ClientRandomization
		for _, client := range s.cfg.Clients {
			if client.ClientID == id {
				quota = client.Quota
				refresh = client.Refresh
				randomization = client.Randomization
				break
			}
		}'''
    t = t.replace(state_lookup, state_lookup_new, 1)
    print("[patch-randomization] State() captures randomization pointer")

state_append = '''		out.Clients = append(out.Clients, ClientState{
			ClientID:  id,
			Refresh:   refresh,
			Quota:     quota,
			Locations: clients[id],
		})'''
if state_append in t and 'Randomization: randomization,' not in t:
    state_append_new = '''		out.Clients = append(out.Clients, ClientState{
			ClientID:      id,
			Refresh:       refresh,
			Quota:         quota,
			Locations:     clients[id],
			Randomization: randomization,
		})'''
    t = t.replace(state_append, state_append_new, 1)
    print("[patch-randomization] State() emits randomization field")

# === 10. Sync Clients + GlobalSettings into supervisor on UpdateSettings ===
# Upstream UpdateSettings only copies Name/Port/SubscriptionPath/Refresh, so
# randomization changes (enable/disable/global) never reach s.cfg.Clients that
# State() reads -> /api/state randomization stayed stale. (Root cause of Task 1.)
update_settings = '''func (s *Supervisor) UpdateSettings(cfg Config) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cfg.Name = cfg.Name
	s.cfg.Port = cfg.Port
	s.cfg.SubscriptionPath = cfg.SubscriptionPath
	s.cfg.Refresh = cfg.Refresh
}'''
if update_settings in t and 's.cfg.Clients = cfg.Clients' not in t:
    update_settings_new = '''func (s *Supervisor) UpdateSettings(cfg Config) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cfg.Name = cfg.Name
	s.cfg.Port = cfg.Port
	s.cfg.SubscriptionPath = cfg.SubscriptionPath
	s.cfg.Refresh = cfg.Refresh
	s.cfg.Clients = cfg.Clients
	s.cfg.GlobalSettings = cfg.GlobalSettings
	s.cfg.RandomizationSecret = cfg.RandomizationSecret
}'''
    t = t.replace(update_settings, update_settings_new, 1)
    print("[patch-randomization] UpdateSettings syncs Clients + GlobalSettings")

p.write_text(t)
print("[patch-randomization] ok")
PY
