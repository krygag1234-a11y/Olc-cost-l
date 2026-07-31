#!/usr/bin/env bash
# Synchronize user-facing randomization type/scope with server crypto state and
# restart only affected clients so new env reaches olcrtc-core.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-rand-crypto-sync] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
changed = False

if "func olcSyncCryptoRandomization(" not in text:
    anchor = "func keyRandomizationHandler(configPath string) http.HandlerFunc {"
    if anchor not in text:
        print("[patch-rand-crypto-sync] ERROR: keyRandomizationHandler anchor not found")
        raise SystemExit(1)
    helper = r'''type olcCryptoEffective struct {
	Enabled  bool
	RandType int
	Secret   string
}

func olcCryptoEffectiveFor(state olcKeyRandCfg, clientID string) olcCryptoEffective {
	if state.Global.Enabled {
		rt := state.Global.RandType
		if rt != 2 {
			rt = 1
		}
		return olcCryptoEffective{Enabled: true, RandType: rt, Secret: state.Secret}
	}
	if client, ok := state.Clients[clientID]; ok && client.Enabled {
		rt := client.RandType
		if rt != 2 {
			rt = 1
		}
		return olcCryptoEffective{Enabled: true, RandType: rt, Secret: state.Secret}
	}
	return olcCryptoEffective{}
}

// olcSyncCryptoRandomization mirrors the visible randomization settings into
// key-randomization.json. Scope client_id disables crypto; crypto/both enables
// it with the same type. The subscription and original instance keys are not changed.
func olcSyncCryptoRandomization(cfg Config) (bool, map[string]bool, error) {
	cfg.ensureClientsFormat()
	olcKeyRandMu.Lock()
	defer olcKeyRandMu.Unlock()

	previous := olcKeyRandLoad()
	desired := olcKeyRandCfg{
		Clients: map[string]olcKeyRandScope{},
		Secret:  cfg.RandomizationSecret,
	}
	cryptoEnabled := olcRandScope(cfg) != "client_id"
	if cryptoEnabled && globalRandomizationEnabled(cfg) {
		rt := cfg.GlobalSettings.Subscription.RandType
		if rt != 2 {
			rt = 1
		}
		desired.Global = olcKeyRandScope{Enabled: true, RandType: rt}
	}
	if cryptoEnabled {
		for _, client := range cfg.Clients {
			if client.Randomization == nil || !client.Randomization.Enabled {
				continue
			}
			rt := client.Randomization.RandType
			if rt != 2 {
				rt = 1
			}
			desired.Clients[client.ClientID] = olcKeyRandScope{Enabled: true, RandType: rt}
		}
	}

	affected := map[string]bool{}
	for _, client := range cfg.Clients {
		before := olcCryptoEffectiveFor(previous, client.ClientID)
		after := olcCryptoEffectiveFor(desired, client.ClientID)
		if before != after {
			affected[client.ClientID] = true
		}
	}
	if reflect.DeepEqual(previous, desired) {
		return false, affected, nil
	}
	if err := olcKeyRandSave(desired); err != nil {
		return false, nil, err
	}
	return true, affected, nil
}

// olcRestartCryptoClients makes changed crypto env effective. Failures are
// logged per location; saved settings remain authoritative and later manual
// restart/reload will converge them.
func olcRestartCryptoClients(cfg Config, affected map[string]bool) {
	if globalSupervisor == nil || len(affected) == 0 {
		return
	}
	cfg.ensureClientsFormat()
	for _, client := range cfg.Clients {
		if !affected[client.ClientID] {
			continue
		}
		for _, location := range client.Locations {
			if err := globalSupervisor.Restart(context.Background(), client.ClientID, location.Endpoint.RoomID, location.Transport.Type); err != nil {
				log.Printf("olc-keyrand: restart %s/%s after crypto change: %v", client.ClientID, location.Endpoint.RoomID, err)
			}
		}
	}
}

'''
    text = text.replace(anchor, helper + anchor, 1)
    changed = True
    print("[patch-rand-crypto-sync] helpers added")

def wire_handler(name: str) -> None:
    global text, changed
    marker = f"func {name}("
    start = text.find(marker)
    if start < 0:
        print(f"[patch-rand-crypto-sync] ERROR: {name} not found")
        raise SystemExit(1)
    end = text.find("\nfunc ", start + len(marker))
    if end < 0:
        end = len(text)
    block = text[start:end]
    if "olcSyncCryptoRandomization(cfg)" in block:
        print(f"[patch-rand-crypto-sync] {name} already wired")
        return
    needle = '''		if globalSupervisor != nil {
			globalSupervisor.UpdateSettings(cfg)
		}'''
    addition = '''		if _, affected, syncErr := olcSyncCryptoRandomization(cfg); syncErr != nil {
			http.Error(w, syncErr.Error(), http.StatusInternalServerError)
			return
		} else {
			olcRestartCryptoClients(cfg, affected)
		}
'''+needle
    if needle not in block:
        print(f"[patch-rand-crypto-sync] ERROR: update anchor missing in {name}")
        raise SystemExit(1)
    block = block.replace(needle, addition, 1)
    text = text[:start] + block + text[end:]
    changed = True
    print(f"[patch-rand-crypto-sync] {name} wired")

for handler in (
    "randomizationEnableHandler",
    "randomizationDisableHandler",
    "randomizationPatchHandler",
    "globalRandomizationHandler",
):
    wire_handler(handler)

# Scope handler has no UpdateSettings call in the older patch; wire directly
# after saveConfig and update the in-memory supervisor settings as well.
scope_start = text.find("func randomizationScopeHandler(")
scope_end = text.find("\nfunc ", scope_start + 1)
scope = text[scope_start:scope_end]
if "olcSyncCryptoRandomization(cfg)" not in scope:
    needle = '''		if err := saveConfig(configPath, cfg); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSONStatus(w, http.StatusOK, map[string]any{"rand_scope": sc})'''
    replacement = '''		if err := saveConfig(configPath, cfg); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if _, affected, syncErr := olcSyncCryptoRandomization(cfg); syncErr != nil {
			http.Error(w, syncErr.Error(), http.StatusInternalServerError)
			return
		} else {
			olcRestartCryptoClients(cfg, affected)
		}
		if globalSupervisor != nil {
			globalSupervisor.UpdateSettings(cfg)
		}
		writeJSONStatus(w, http.StatusOK, map[string]any{"rand_scope": sc})'''
    if needle not in scope:
        print("[patch-rand-crypto-sync] ERROR: scope save anchor missing")
        raise SystemExit(1)
    scope = scope.replace(needle, replacement, 1)
    text = text[:scope_start] + scope + text[scope_end:]
    changed = True
    print("[patch-rand-crypto-sync] randomizationScopeHandler wired")

if changed:
    path.write_text(text)
print("[patch-rand-crypto-sync] ok")
PY
