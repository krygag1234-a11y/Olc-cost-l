#!/usr/bin/env bash
# Olc-cost-l backend: GET /api/instances/info?client_id=&room_id= — сводка по
# ОТДЕЛЬНОМУ инстансу для Info-модалки панели:
#   {orig_key, key_rand:{enabled,rand_type,randomized_key,dynamic}, traffic:{available,used_bytes}}
# - orig_key: оригинальный ключ шифрования инстанса (loc.Endpoint.Key) — админ-панель.
# - randomized_key: тип1 — статичный HMAC(secret,origKey); тип2 — ТЕКУЩИЙ посекундный
#   (dynamic=true, панель опрашивает раз в секунду). Если рандомизация ключей выкл — пусто.
# - traffic: best-effort из QuotaEnforcer (доступно только при netns/квотах).
# Idempotent. Target: manager cmd/olcrtc-manager/main.go.
# Run ПОСЛЕ key-randomization-api (нужны olcKeyRandForClient/olcAltKeysForLocation).
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-instance-info-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Глобальная ссылка на QuotaEnforcer (для per-instance traffic) ---
if 'panelQuota *QuotaEnforcer' not in t:
    anchor = '\tpanelSupervisor *Supervisor'
    if anchor in t:
        t = t.replace(anchor, anchor + '\n\tpanelQuota      *QuotaEnforcer', 1)
        changed = True
        print("[patch-instance-info-api] var panelQuota: ok")
    else:
        print("[patch-instance-info-api] WARN: panelSupervisor var anchor not found")
else:
    print("[patch-instance-info-api] var panelQuota: already applied")

if 'panelQuota = quotaEnforcer' not in t:
    anchor = '\tquotaEnforcer := NewQuotaEnforcer(configPath, supervisor)'
    if anchor in t:
        t = t.replace(anchor, anchor + '\n\tpanelQuota = quotaEnforcer', 1)
        changed = True
        print("[patch-instance-info-api] assign panelQuota: ok")
    else:
        print("[patch-instance-info-api] WARN: quotaEnforcer assign anchor not found")
else:
    print("[patch-instance-info-api] assign panelQuota: already applied")

# --- 2. Роут ---
route_anchor = '\thandler.Handle("/api/access/connections", adminAuth(http.HandlerFunc(accessConnectionsHandler)))'
route_add = route_anchor + '''
	// Olc-cost-l: сводка по отдельному инстансу (ключи + трафик) для Info-модалки.
	handler.Handle("/api/instances/info", adminAuth(instanceInfoHandler(configPath)))'''
if '/api/instances/info' in t:
    print("[patch-instance-info-api] route: already applied")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1)
    changed = True
    print("[patch-instance-info-api] route: ok")
else:
    print("[patch-instance-info-api] WARN: access/connections route anchor not found")

# --- 3. Метод QuotaEnforcer.LocationBytesForKey (best-effort per-instance) ---
if 'func (q *QuotaEnforcer) LocationBytesForKey(' not in t:
    fn_anchor = 'func (q *QuotaEnforcer) ruleBytes('
    fn_block = '''// LocationBytesForKey — текущий счётчик байт для инстанса (по locationKey).
// Best-effort: доступно только если для инстанса зарегистрировано правило квоты
// (netns/cgroup). Возвращает (bytes, true) при наличии правила.
func (q *QuotaEnforcer) LocationBytesForKey(key string) (uint64, bool) {
	if q == nil {
		return 0, false
	}
	q.mu.Lock()
	rule, ok := q.rules[key]
	q.mu.Unlock()
	if !ok {
		return 0, false
	}
	b, err := q.ruleBytes(context.Background(), rule)
	if err != nil {
		return 0, false
	}
	return b, true
}

'''
    if fn_anchor in t:
        t = t.replace(fn_anchor, fn_block + fn_anchor, 1)
        changed = True
        print("[patch-instance-info-api] LocationBytesForKey: ok")
    else:
        print("[patch-instance-info-api] WARN: ruleBytes anchor not found")
else:
    print("[patch-instance-info-api] LocationBytesForKey: already applied")

# --- 4. Хендлер ---
if 'func instanceInfoHandler(' not in t:
    fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
    fn_block = r'''// instanceInfoHandler — сводка по инстансу: ключи (ориг + рандомизированный) и
// best-effort трафик. Для тип2 возвращает ТЕКУЩИЙ посекундный рандомизированный
// ключ (dynamic=true) — панель опрашивает раз в секунду.
func instanceInfoHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]any{"error": "method not allowed"})
			return
		}
		clientID := strings.TrimSpace(r.URL.Query().Get("client_id"))
		roomID := strings.TrimSpace(r.URL.Query().Get("room_id"))
		if clientID == "" || roomID == "" {
			writeJSONStatus(w, http.StatusBadRequest, map[string]any{"error": "client_id and room_id required"})
			return
		}
		cfg, err := loadConfig(configPath)
		if err != nil {
			writeJSONStatus(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
			return
		}
		cfg.ensureClientsFormat()
		var found *Location
		var foundClient Client
		for ci := range cfg.Clients {
			if cfg.Clients[ci].ClientID != clientID {
				continue
			}
			for li := range cfg.Clients[ci].Locations {
				if strings.TrimSpace(cfg.Clients[ci].Locations[li].Endpoint.RoomID) == roomID {
					found = &cfg.Clients[ci].Locations[li]
					foundClient = cfg.Clients[ci]
					break
				}
			}
			break
		}
		if found == nil {
			writeJSONStatus(w, http.StatusNotFound, map[string]any{"error": "instance not found"})
			return
		}

		// Рандомизированная версия ключа отражает РЕАЛЬНУЮ рандомизацию клиента
		// (client_id-рандомизация: глоб. или per-client — randTypeFor), а НЕ
		// отдельную инертную крипто-рандомизацию ключей (эпик A). Тип2 → живой
		// посекундный ключ (панель опрашивает раз в секунду). Значение —
		// производная HMAC(secret, origKeyBytes[||unixSec]) для отображения.
		keyRand := map[string]any{"enabled": false, "rand_type": 0, "randomized_key": "", "dynamic": false}
		rt := randTypeFor(foundClient, cfg)
		secret := cfg.RandomizationSecret
		if rt > 0 && secret != "" {
			keyRand["enabled"] = true
			keyRand["rand_type"] = rt
			if rt == 2 {
				keyRand["dynamic"] = true
				if rk := olcInstanceRandKeyAt(secret, found.Endpoint.Key, time.Now().Unix()); rk != "" {
					keyRand["randomized_key"] = rk
				}
			} else {
				if rk := olcInstanceRandKeyStatic(secret, found.Endpoint.Key); rk != "" {
					keyRand["randomized_key"] = rk
				}
			}
		}

		traffic := map[string]any{"available": false, "used_bytes": 0}
		if panelQuota != nil {
			if b, ok := panelQuota.LocationBytesForKey(locationKey(*found)); ok {
				traffic["available"] = true
				traffic["used_bytes"] = b
			}
		}

		writeJSON(w, map[string]any{
			"client_id": clientID,
			"room_id":   roomID,
			"name":      found.Name,
			"orig_key":  found.Endpoint.Key,
			"key_rand":  keyRand,
			"traffic":   traffic,
		})
	}
}

// olcInstanceRandKeyAt — посекундный рандомизированный ключ (тип2):
// HMAC(secret, origKeyBytes || unixSec)[:32] -> hex(64). Пусто при плохих входных.
func olcInstanceRandKeyAt(secret, origKeyHex string, unixSec int64) string {
	if secret == "" {
		return ""
	}
	ob, err := hex.DecodeString(strings.TrimSpace(origKeyHex))
	if err != nil || len(ob) != 32 {
		return ""
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(ob)
	var b [8]byte
	binary.BigEndian.PutUint64(b[:], uint64(unixSec))
	mac.Write(b[:])
	sum := mac.Sum(nil)
	return hex.EncodeToString(sum[:32])
}

// olcInstanceRandKeyStatic — статичный рандомизированный ключ (тип1):
// HMAC(secret, origKeyBytes)[:32] -> hex(64). Пусто при плохих входных.
func olcInstanceRandKeyStatic(secret, origKeyHex string) string {
	if secret == "" {
		return ""
	}
	ob, err := hex.DecodeString(strings.TrimSpace(origKeyHex))
	if err != nil || len(ob) != 32 {
		return ""
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(ob)
	sum := mac.Sum(nil)
	return hex.EncodeToString(sum[:32])
}

'''
    if fn_anchor in t:
        t = t.replace(fn_anchor, fn_block + fn_anchor, 1)
        changed = True
        print("[patch-instance-info-api] handler: ok")
    else:
        print("[patch-instance-info-api] WARN: writeJSON anchor not found")
else:
    print("[patch-instance-info-api] handler: already applied")

# --- 5. Гарантия импортов (binary/encoding) ---
for imp in ('"encoding/binary"',):
    if imp not in t:
        anc = '\t"encoding/hex"'
        if anc in t:
            t = t.replace(anc, anc + '\n' + '\t' + imp, 1)
            changed = True
            print(f"[patch-instance-info-api] import {imp}: ok")
        else:
            print(f"[patch-instance-info-api] WARN: hex import anchor not found for {imp}")

if changed:
    f.write_text(t)
    print("[patch-instance-info-api] OK: main.go updated")
else:
    print("[patch-instance-info-api] no changes (idempotent)")
PY
