#!/usr/bin/env bash
# Olc-cost-l backend: cleanup смежных конфигов при УДАЛЕНИИ клиента/локации (Баг 1, V2).
# Не даёт старым выборочным настройкам и журналам всплыть после повторного создания ID.
# Рандомизация клиента (Client.Randomization) — поле самого клиента в config.json,
# оно исчезает вместе с клиентом при deleteClient, отдельной чистки не требует.
# Чистит access control/attempts/connections, key rotation rounds/settings и key randomization.
# Требует соответствующие patch-функции; Go разрешает объявить их ниже по файлу.
# Run ПОСЛЕ access-control/connections и ДО key-rotation/key-randomization. Idempotent.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-delete-client-cleanup] ERROR: $MAIN_GO not found"; exit 1; }

if grep -q 'olcCleanupDeletedClientV2' "$MAIN_GO"; then
  echo "[patch-delete-client-cleanup] already applied"
  exit 0
fi

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# V2 cleans every separate per-client state introduced by selective features.
# Client.Randomization lives inside config.json and is removed with the client itself.
anchor = 'func deleteClient(configPath, clientID string) error {'
if anchor not in t:
    print("[patch-delete-client-cleanup] ERROR: deleteClient anchor not found")
    sys.exit(1)

if 'func olcCleanupDeletedClientV2(' not in t:
    helper = r'''// olcCleanupDeletedClientV2 removes all per-client state stored outside config.json.
// Cleanup is best-effort after config.json has been saved: a stale auxiliary file must not
// resurrect selective settings if the same client ID is created again.
func olcCleanupDeletedClientV2(clientID string) {
	clientID = strings.TrimSpace(clientID)
	if clientID == "" {
		return
	}

	olcAccessMu.Lock()
	ac := olcAccessLoad()
	if ac.Clients != nil {
		if _, ok := ac.Clients[clientID]; ok {
			delete(ac.Clients, clientID)
			if err := olcAccessSave(ac); err != nil {
				log.Printf("olc-delete: access cleanup for client %q: %v", clientID, err)
			}
		}
	}
	attempts := olcAccessLoadAttempts()
	keptAttempts := attempts[:0]
	for _, attempt := range attempts {
		if attempt.ClientID != clientID {
			keptAttempts = append(keptAttempts, attempt)
		}
	}
	if len(keptAttempts) != len(attempts) {
		_olcAccessWriteAttempts(keptAttempts)
	}
	olcAccessMu.Unlock()

	olcConnJournalMu.Lock()
	olcConnJournalLoad()
	keptConnections := olcConnJournal[:0]
	for _, record := range olcConnJournal {
		if record.ClientID != clientID {
			keptConnections = append(keptConnections, record)
		}
	}
	olcConnJournal = keptConnections
	if olcConnClearedClients == nil {
		olcConnClearedClients = map[string]string{}
	}
	// Prevent buffered pre-delete log lines from recreating removed records before reload finishes.
	olcConnClearedClients[clientID] = time.Now().UTC().Format(time.RFC3339)
	olcConnJournalSave()
	olcConnJournalMu.Unlock()

	olcKeyRotationMu.Lock()
	rotation := olcKeyRotationLoad()
	rotationChanged := false
	if _, ok := rotation.Clients[clientID]; ok {
		delete(rotation.Clients, clientID)
		rotationChanged = true
	}
	if _, ok := rotation.Rounds[clientID]; ok {
		delete(rotation.Rounds, clientID)
		rotationChanged = true
	}
	if rotationChanged {
		if err := olcKeyRotationSave(rotation); err != nil {
			log.Printf("olc-delete: key rotation cleanup for client %q: %v", clientID, err)
		}
	}
	olcKeyRotationMu.Unlock()

	olcKeyRandMu.Lock()
	keyRand := olcKeyRandLoad()
	if _, ok := keyRand.Clients[clientID]; ok {
		delete(keyRand.Clients, clientID)
		if err := olcKeyRandSave(keyRand); err != nil {
			log.Printf("olc-delete: key randomization cleanup for client %q: %v", clientID, err)
		}
	}
	olcKeyRandMu.Unlock()
}

// olcCleanupDeletedLocationV2 removes selective room references and connection history.
// Rotation and both randomization settings are client-scoped, so they remain for the client.
func olcCleanupDeletedLocationV2(clientID, roomID string) {
	clientID = strings.TrimSpace(clientID)
	roomID = strings.TrimSpace(roomID)
	if clientID == "" || roomID == "" {
		return
	}

	olcAccessMu.Lock()
	ac := olcAccessLoad()
	changed := false
	filterRooms := func(rooms []string) []string {
		kept := rooms[:0]
		for _, room := range rooms {
			if room != roomID {
				kept = append(kept, room)
			} else {
				changed = true
			}
		}
		return kept
	}
	ac.ConnInstances = filterRooms(ac.ConnInstances)
	if clientAccess := ac.Clients[clientID]; clientAccess != nil {
		clientAccess.ConnInstances = filterRooms(clientAccess.ConnInstances)
	}
	if changed {
		if err := olcAccessSave(ac); err != nil {
			log.Printf("olc-delete: access cleanup for location %q/%q: %v", clientID, roomID, err)
		}
	}
	olcAccessMu.Unlock()

	olcConnJournalMu.Lock()
	olcConnJournalLoad()
	kept := olcConnJournal[:0]
	for _, record := range olcConnJournal {
		if record.ClientID != clientID || record.RoomID != roomID {
			kept = append(kept, record)
		}
	}
	if len(kept) != len(olcConnJournal) {
		olcConnJournal = kept
		olcConnJournalSave()
	}
	olcConnJournalMu.Unlock()
}

'''
    t = t.replace(anchor, helper + anchor, 1)
    changed = True
    print("[patch-delete-client-cleanup] V2 cleanup helpers added")

# 2. Врезка вызова в конце deleteClient (внутри тела функции).
fn_start = t.index(anchor)
fn_end = t.index('\n}\n', fn_start) + len('\n}\n')
block = t[fn_start:fn_end]
old_tail = '\treturn saveConfig(configPath, cfg)\n}'
new_tail = (
    '\tif err := saveConfig(configPath, cfg); err != nil {\n'
    '\t\treturn err\n'
    '\t}\n'
    '\tolcCleanupDeletedClientV2(clientID)\n'
    '\treturn nil\n'
    '}'
)
if 'olcCleanupDeletedClientV2(clientID)' not in block:
    block = block.replace('\tolcCleanupClientAccess(clientID)\n', '')
    if old_tail not in block:
        print("[patch-delete-client-cleanup] ERROR: deleteClient tail anchor not found")
        sys.exit(1)
    new_block = block.replace(old_tail, new_tail, 1)
    t = t[:fn_start] + new_block + t[fn_end:]
    changed = True
    print("[patch-delete-client-cleanup] deleteClient wired to V2 cleanup")

# 3. Wire location cleanup after config.json is saved.
loc_anchor = 'func deleteLocation(configPath, clientID, roomID string) error {'
if loc_anchor not in t:
    print("[patch-delete-client-cleanup] ERROR: deleteLocation anchor not found")
    sys.exit(1)
loc_start = t.index(loc_anchor)
loc_end = t.index('\n}\n', loc_start) + len('\n}\n')
loc_block = t[loc_start:loc_end]
loc_old = '\t\treturn saveConfig(configPath, cfg)\n'
loc_new = (
    '\t\tif err := saveConfig(configPath, cfg); err != nil {\n'
    '\t\t\treturn err\n'
    '\t\t}\n'
    '\t\tolcCleanupDeletedLocationV2(clientID, roomID)\n'
    '\t\treturn nil\n'
)
if 'olcCleanupDeletedLocationV2(clientID, roomID)' not in loc_block:
    if loc_old not in loc_block:
        print("[patch-delete-client-cleanup] ERROR: deleteLocation tail anchor not found")
        sys.exit(1)
    new_loc_block = loc_block.replace(loc_old, loc_new, 1)
    t = t[:loc_start] + new_loc_block + t[loc_end:]
    changed = True
    print("[patch-delete-client-cleanup] deleteLocation wired to V2 cleanup")

if changed:
    f.write_text(t)
print("[patch-delete-client-cleanup] ok")
PY
