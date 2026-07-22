#!/usr/bin/env bash
# Olc-cost-l backend: РАНДОМИЗАЦИЯ КЛЮЧЕЙ (эпик A), ЧАСТЬ 5a — manager: состояние
# + API + вывод рандомизированного ключа (тип1) + передача в инстанс.
#
# СЕРВЕР-ONLY. Меняется РАНДОМИЗИРОВАННЫЙ ключ (HMAC(secret, origKeyBytes)), НЕ
# оригинальный. Состояние — отдельный файл /var/lib/olcrtc/key-randomization.json
# {global{enabled,rand_type}, clients{id{enabled,rand_type}}, secret}. Секрет
# копируется из config.json (RandomizationSecret) при сохранении, чтобы
# startInstance (без configPath) мог вывести ключ. Тип1 = статичный alt-ключ,
# передаётся инстансу через env OLCRTC_ALT_KEYS (читает core key-rand часть 3).
# Тип2 (посекундный) — часть 6 (core деривит сам), тут пока тип1.
# Дефолт ВЫКЛ (нет env → core single-cipher → ноль влияния).
# API (adminAuth): GET/PATCH /api/settings/key-randomization {global_enabled,rand_type};
#   POST /api/clients/:id/key-randomization {enabled,rand_type}.
# Idempotent. Target: manager main.go. Run ПОСЛЕ key-rotation (роутер /api/clients/,
# subscription-api) и access-control-api.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-key-rand-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Роут глобальной настройки (после key-rotation route) ---
route_anchor = '\thandler.Handle("/api/settings/key-rotation", adminAuth(keyRotationHandler(configPath)))'
route_add = route_anchor + '''
	// Olc-cost-l: рандомизация ключей (эпик A) — глобальная настройка.
	handler.Handle("/api/settings/key-randomization", adminAuth(keyRandomizationHandler(configPath)))'''
if '/api/settings/key-randomization' in t:
    print("[patch-key-rand-api] global route already present")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1); changed = True
    print("[patch-key-rand-api] registered /api/settings/key-randomization route")
else:
    print("[patch-key-rand-api] WARN: key-rotation route anchor not found — skip global route")

# --- 2. Per-client роут (после key-rotation в /api/clients/ роутере) ---
cl_anchor = '''		if strings.HasSuffix(urlPath, "/key-rotation") {
			clientKeyRotationHandler(configPath)(w, r)
			return
		}'''
cl_add = cl_anchor + '''
		if strings.HasSuffix(urlPath, "/key-randomization") {
			clientKeyRandomizationHandler(configPath)(w, r)
			return
		}'''
if 'clientKeyRandomizationHandler(configPath)(w, r)' in t:
    print("[patch-key-rand-api] client route already present")
elif cl_anchor in t:
    t = t.replace(cl_anchor, cl_add, 1); changed = True
    print("[patch-key-rand-api] registered /api/clients/:id/key-randomization route")
else:
    print("[patch-key-rand-api] WARN: key-rotation client route anchor not found — skip client route")

# --- 3. Реализация (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// ============================================================================
// Olc-cost-l: РАНДОМИЗАЦИЯ КЛЮЧЕЙ (эпик A, часть 5a). Состояние в отдельном файле
// /var/lib/olcrtc/key-randomization.json. Меняется РАНДОМИЗИРОВАННЫЙ ключ (вывод
// HMAC(secret, origKeyBytes)), оригинальный ключ инстанса НЕ трогается.
// ============================================================================

const olcKeyRandPath = "/var/lib/olcrtc/key-randomization.json"

var olcKeyRandMu sync.Mutex

type olcKeyRandScope struct {
	Enabled  bool `json:"enabled"`
	RandType int  `json:"rand_type"` // 1 статичный / 2 посекундный (часть 6)
}

// olcKeyRandCfg — состояние рандомизации ключей. Secret копируется из config.json
// (RandomizationSecret) при каждом сохранении, чтобы startInstance (без доступа к
// configPath) мог вывести рандомизированный ключ.
type olcKeyRandCfg struct {
	Global  olcKeyRandScope            `json:"global"`
	Clients map[string]olcKeyRandScope `json:"clients,omitempty"`
	Secret  string                     `json:"secret,omitempty"`
}

func olcKeyRandLoad() olcKeyRandCfg {
	rc := olcKeyRandCfg{Clients: map[string]olcKeyRandScope{}}
	data, err := os.ReadFile(olcKeyRandPath)
	if err != nil {
		return rc
	}
	_ = json.Unmarshal(data, &rc)
	if rc.Clients == nil {
		rc.Clients = map[string]olcKeyRandScope{}
	}
	return rc
}

func olcKeyRandSave(rc olcKeyRandCfg) error {
	if err := os.MkdirAll(filepath.Dir(olcKeyRandPath), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(rc, "", "  ")
	if err != nil {
		return err
	}
	tmp := olcKeyRandPath + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, olcKeyRandPath)
}

// olcKeyRandForClient — включена ли рандомизация ключей для клиента + тип + секрет.
func olcKeyRandForClient(clientID string) (bool, int, string) {
	rc := olcKeyRandLoad()
	if rc.Global.Enabled {
		rt := rc.Global.RandType
		if rt != 2 {
			rt = 1
		}
		return true, rt, rc.Secret
	}
	if c, ok := rc.Clients[clientID]; ok && c.Enabled {
		rt := c.RandType
		if rt != 2 {
			rt = 1
		}
		return true, rt, rc.Secret
	}
	return false, 0, rc.Secret
}

// olcAltKeysForLocation — рандомизированные ключи для инстанса (env OLCRTC_ALT_KEYS).
// Тип1: один статичный ключ HMAC(secret, origKeyBytes)[:32] → hex(64). Тип2:
// посекундный — деривит САМ core (часть 6), тут пусто. Оригинальный ключ инстанса
// (loc.Endpoint.Key) НЕ меняется — это второй, производный ключ расшифровки.
func olcAltKeysForLocation(loc Location) []string {
	en, rt, secret := olcKeyRandForClient(loc.ClientID)
	if !en || secret == "" || rt == 2 {
		return nil
	}
	ob, err := hex.DecodeString(strings.TrimSpace(loc.Endpoint.Key))
	if err != nil || len(ob) != 32 {
		return nil
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(ob)
	sum := mac.Sum(nil) // 32 байта
	return []string{hex.EncodeToString(sum[:32])}
}

func keyRandomizationHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			writeJSON(w, olcKeyRandLoad())
		case http.MethodPatch, http.MethodPut, http.MethodPost:
			var in struct {
				GlobalEnabled *bool `json:"global_enabled"`
				RandType      *int  `json:"rand_type"`
			}
			if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
				writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			olcKeyRandMu.Lock()
			rc := olcKeyRandLoad()
			if in.GlobalEnabled != nil {
				rc.Global.Enabled = *in.GlobalEnabled
			}
			if in.RandType != nil {
				if *in.RandType == 2 {
					rc.Global.RandType = 2
				} else {
					rc.Global.RandType = 1
				}
			}
			// Копируем актуальный секрет из config.json.
			if cfg, cerr := loadConfig(configPath); cerr == nil {
				rc.Secret = cfg.RandomizationSecret
			}
			err := olcKeyRandSave(rc)
			olcKeyRandMu.Unlock()
			if err != nil {
				writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			log.Printf("olc-keyrand: global saved: enabled=%t rand_type=%d clients=%d", rc.Global.Enabled, rc.Global.RandType, len(rc.Clients))
			writeJSON(w, rc)
		default:
			writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	}
}

func clientKeyRandomizationHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimPrefix(r.URL.Path, "/api/clients/")
		id = strings.TrimSuffix(id, "/key-randomization")
		id = strings.TrimSpace(id)
		if id == "" {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "client_id required"})
			return
		}
		if r.Method != http.MethodPost && r.Method != http.MethodPut && r.Method != http.MethodPatch {
			writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
			return
		}
		var in struct {
			Enabled  *bool `json:"enabled"`
			RandType *int  `json:"rand_type"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		olcKeyRandMu.Lock()
		rc := olcKeyRandLoad()
		if rc.Clients == nil {
			rc.Clients = map[string]olcKeyRandScope{}
		}
		cur := rc.Clients[id]
		if in.Enabled != nil {
			cur.Enabled = *in.Enabled
		}
		if in.RandType != nil {
			if *in.RandType == 2 {
				cur.RandType = 2
			} else {
				cur.RandType = 1
			}
		}
		if cur.RandType == 0 {
			cur.RandType = 1
		}
		if cur.Enabled {
			rc.Clients[id] = cur
		} else {
			delete(rc.Clients, id)
		}
		if cfg, cerr := loadConfig(configPath); cerr == nil {
			rc.Secret = cfg.RandomizationSecret
		}
		err := olcKeyRandSave(rc)
		olcKeyRandMu.Unlock()
		if err != nil {
			writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		log.Printf("olc-keyrand: client %s saved: enabled=%v rand_type=%d", id, in.Enabled != nil && *in.Enabled, cur.RandType)
		writeJSON(w, rc)
	}
}

'''
if 'func keyRandomizationHandler(' in t:
    print("[patch-key-rand-api] implementation already present")
elif fn_anchor in t:
    t = t.replace(fn_anchor, fn_block + fn_anchor, 1); changed = True
    print("[patch-key-rand-api] added key-randomization implementation")
else:
    print("[patch-key-rand-api] WARN: writeJSON anchor not found — skip implementation")

if changed:
    f.write_text(t)
    print("[patch-key-rand-api] OK: main.go updated")
else:
    print("[patch-key-rand-api] no changes (idempotent)")
PY
