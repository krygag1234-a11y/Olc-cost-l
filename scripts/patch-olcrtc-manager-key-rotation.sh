#!/usr/bin/env bash
# Olc-cost-l backend: «♻️ Автосмена ключей» (Z5-B) — периодическая ротация
# ОРИГИНАЛЬНОГО ключа шифрования (Endpoint.Key) инстансов.
#
# Идея (спека юзера, сессия №18): раз в N часов (N = интервал автообновления
# подписки = subscriptionRefreshHours, per-client если выборочно / глобальный
# если глобально) сервер перегенерирует ключи ВСЕХ инстансов клиента. Клиент
# подхватывает новые ключи при следующем автообновлении подписки (olcbox фетчит
# по profile-update-interval). Защита от УТЁКШЕЙ подписки (Урок 67, сервер-
# двойник): слитый ключ протухает за N.
#
# КРИТИЧНО (уточнение юзера): ротация НЕ рвёт активные туннели. Инстанс с
# peers>0 ПРОПУСКАЕТСЯ до СЛЕДУЮЩЕГО круга (не ротируется вне очереди) — ждёт
# окончания сессии и ротируется вместе со всеми на следующем круге. Раунд у
# клиента наступает раз в N часов; занятый инстанс на каждом раунде
# пропускается, пока peers не станет 0.
#
# МОДЕЛЬ ROTATE-ON-FETCH (сессия №19): ротация происходит НЕ по серверному
# таймеру, а В МОМЕНТ ФЕТЧА подписки клиентом (olcKeyRotationOnFetch в
# subscriptionHandler). olcbox фетчит подписку РОВНО когда её применяет
# (LocationsDatasource.refreshDueSubscriptions: fetch только для DUE-URL по
# интервалу N; подтверждено кодом olcbox) → новые ключи уходят клиенту В ТОМ ЖЕ
# ответе → ЗАЗОР НЕДОСТУПНОСТИ = 0 (клиент не остаётся со старым ключом).
#
# Хранение состояния — ОТДЕЛЬНЫЙ файл /var/lib/olcrtc/key-rotation.json (НЕ
# трогаем структуру Config → нет ломки якорей, Урок 58). Ротация меняет
# Endpoint.Key в config.json + reload() (Supervisor.Reload рестартует ТОЛЬКО
# инстансы с изменившимся ключом — DeepEqual; занятые с прежним ключом не
# трогаются). Дефолт — ВЫКЛЮЧЕНО (нулевое влияние на прод до включения юзером).
#
# API (adminAuth): GET/PATCH /api/settings/key-rotation (глоб.);
#   POST /api/clients/:id/key-rotation {enabled}.
# Idempotent. Target: manager main.go.
# Run ПОСЛЕ: subscription-api (роутер /api/clients/), subscription-update-interval
# (subscriptionRefreshHours), access-drop-sessions (panelSupervisor использование),
# peer-summary (PeerSummary 4-возврата).
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-key-rotation] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Роут глобальной настройки (после /api/access/client) ---
route_anchor = '\thandler.Handle("/api/access/client", adminAuth(http.HandlerFunc(accessClientHandler)))'
route_add = route_anchor + '''
	// Olc-cost-l: автосмена ключей (Z5-B) — глоб. настройка + путь конфига для ротации.
	olcConfigPath = configPath
	handler.Handle("/api/settings/key-rotation", adminAuth(keyRotationHandler(configPath)))'''
if '/api/settings/key-rotation' in t:
    print("[patch-key-rotation] global route already present")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1); changed = True
    print("[patch-key-rotation] registered /api/settings/key-rotation route")
else:
    print("[patch-key-rotation] WARN: /api/access/client anchor not found — skip global route")

# --- 2. Per-client роут в существующем /api/clients/ роутере (после subscription-url) ---
cl_anchor = '''		if strings.HasSuffix(urlPath, "/subscription-url") {
			subscriptionURLHandler(configPath)(w, r)
			return
		}'''
cl_add = cl_anchor + '''
		if strings.HasSuffix(urlPath, "/key-rotation") {
			clientKeyRotationHandler(configPath)(w, r)
			return
		}'''
if 'clientKeyRotationHandler(configPath)(w, r)' in t:
    print("[patch-key-rotation] client route already present")
elif cl_anchor in t:
    t = t.replace(cl_anchor, cl_add, 1); changed = True
    print("[patch-key-rotation] registered /api/clients/:id/key-rotation route")
else:
    print("[patch-key-rotation] WARN: subscription-url route anchor not found — skip client route")

# --- 3. Вызов ротации НА МОМЕНТ ФЕТЧА подписки (rotate-on-fetch) в subscriptionHandler.
# olcbox фетчит подписку РОВНО когда применяет её (refreshDueSubscriptions: fetch
# только для DUE-URL, интервал N) → ротируем свободные инстансы клиента и отдаём
# НОВЫЕ ключи в ЭТОМ ЖЕ ответе → зазор недоступности = 0. Ставим ПОСЛЕ резолва
# client_id и ДО построения тела подписки (SubscriptionForClient читает свежий cfg).
fetch_anchor = '''		resolvedClientID, err := olcResolveClientIDWithAccess(requestedID, cfg, olcActive && olcAllowedDev && !olcDeny)
		if err != nil {
			http.NotFound(w, r)
			return
		}
'''
fetch_add = fetch_anchor + '''
		// Автосмена ключей (Z5-B): ротация на МОМЕНТ фетча подписки (синхронно с
		// автообновлением olcbox — фетч==применение). Свободные инстансы клиента
		// получают новый ключ и отдаются в ЭТОМ же ответе; занятые пропускаются.
		olcKeyRotationOnFetch(supervisor, resolvedClientID)
'''
if 'olcKeyRotationOnFetch(supervisor, resolvedClientID)' in t:
    print("[patch-key-rotation] rotate-on-fetch call already present")
elif fetch_anchor in t:
    t = t.replace(fetch_anchor, fetch_add, 1); changed = True
    print("[patch-key-rotation] injected rotate-on-fetch into subscriptionHandler")
else:
    print("[patch-key-rotation] WARN: subscriptionHandler resolve anchor not found — rotation NOT wired")

# --- 4. Реализация (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// ============================================================================
// Olc-cost-l: «♻️ Автосмена ключей» (Z5-B). Перегенерация ОРИГИНАЛЬНОГО ключа
// шифрования инстансов НА МОМЕНТ ФЕТЧА подписки клиентом (синхронно с
// автообновлением olcbox — фетч==применение → нет зазора недоступности).
// Состояние — отдельный файл /var/lib/olcrtc/key-rotation.json (Config не
// трогаем). Ротация ждёт peers=0 на инстансе (занятые — до следующего круга).
// См. хендофф Задача №5.
// ============================================================================

const olcKeyRotationPath = "/var/lib/olcrtc/key-rotation.json"

var olcKeyRotationMu sync.Mutex

// olcConfigPath — путь к config.json (устанавливается при регистрации роутов),
// нужен ротации, вызываемой из subscriptionHandler (у него нет configPath).
var olcConfigPath string

// olcKeyRotationCfg — состояние автосмены ключей.
//   GlobalEnabled — включено ГЛОБАЛЬНО (для всех клиентов+инстансов).
//   Clients[clientID]=true — включено ВЫБОРОЧНО для этой подписки.
//   Rounds[clientID] — RFC3339 время последнего КРУГА ротации клиента (для
//     отсчёта интервала N часов; занятые инстансы ждут следующего круга).
type olcKeyRotationCfg struct {
	GlobalEnabled bool              `json:"global_enabled"`
	Clients       map[string]bool   `json:"clients,omitempty"`
	Rounds        map[string]string `json:"rounds,omitempty"`
}

func olcKeyRotationLoad() olcKeyRotationCfg {
	rc := olcKeyRotationCfg{Clients: map[string]bool{}, Rounds: map[string]string{}}
	data, err := os.ReadFile(olcKeyRotationPath)
	if err != nil {
		return rc
	}
	_ = json.Unmarshal(data, &rc)
	if rc.Clients == nil {
		rc.Clients = map[string]bool{}
	}
	if rc.Rounds == nil {
		rc.Rounds = map[string]string{}
	}
	return rc
}

func olcKeyRotationSave(rc olcKeyRotationCfg) error {
	if err := os.MkdirAll(filepath.Dir(olcKeyRotationPath), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(rc, "", "  ")
	if err != nil {
		return err
	}
	tmp := olcKeyRotationPath + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, olcKeyRotationPath)
}

func olcKeyRotationEnabledFor(rc olcKeyRotationCfg, clientID string) bool {
	return rc.GlobalEnabled || rc.Clients[clientID]
}

// olcInstancePeerCount — снимок числа живых пиров по инстансам (ключ =
// locationKey). Источник — panelSupervisor (то же, что /api/state). Инстанс без
// peer-summary трактуем как 0 (не подключён) — как в State().
func olcInstancePeerCount() map[string]int {
	out := map[string]int{}
	if panelSupervisor == nil {
		return out
	}
	panelSupervisor.mu.RLock()
	procs := make(map[string]*process, len(panelSupervisor.processes))
	for k, p := range panelSupervisor.processes {
		procs[k] = p
	}
	panelSupervisor.mu.RUnlock()
	for k, p := range procs {
		if p == nil || p.logs == nil {
			continue
		}
		if pc, _, _, ok := p.logs.PeerSummary(); ok {
			out[k] = pc
		}
	}
	return out
}

// olcKeyRotationOnFetch — ротация НА МОМЕНТ ФЕТЧА подписки клиентом. Вызывается
// из subscriptionHandler ПОСЛЕ резолва client_id и ДО построения тела подписки.
// olcbox фетчит подписку РОВНО когда её применяет (refreshDueSubscriptions: fetch
// только для DUE-URL по интервалу N) → ротируем СВОБОДНЫЕ инстансы этого клиента
// и отдаём НОВЫЕ ключи в ЭТОМ ЖЕ ответе → нет зазора недоступности. Гейт по N
// (rounds[clientID]) защищает от лишних ротаций при частых фетчах (curl/ручной
// refresh). ЗАНЯТЫЕ инстансы (peers>0 — клиент как раз ими пользуется)
// пропускаются: их ключ не меняется, живой туннель не рвётся.
func olcKeyRotationOnFetch(supervisor *Supervisor, clientID string) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("olc-keyrot: panic recovered: %v", r)
		}
	}()
	clientID = strings.TrimSpace(clientID)
	if clientID == "" || supervisor == nil || olcConfigPath == "" {
		return
	}
	olcKeyRotationMu.Lock()
	defer olcKeyRotationMu.Unlock()

	rc := olcKeyRotationLoad()
	if !olcKeyRotationEnabledFor(rc, clientID) {
		return // ротация для этого клиента не включена — инертно (только чтение мелкого файла)
	}
	cfg, err := loadConfig(olcConfigPath)
	if err != nil {
		log.Printf("olc-keyrot: load config failed: %v", err)
		return
	}
	cfg.ensureClientsFormat()
	n := subscriptionRefreshHours(cfg, clientID)
	if n <= 0 {
		n = 24 // дефолт olcbox
	}
	now := time.Now().UTC()
	lastStr := rc.Rounds[clientID]
	if lastStr == "" {
		// Первый фетч под ротацией: фиксируем точку отсчёта, НЕ ротируя сразу
		// (первый круг — на СЛЕДУЮЩЕМ фетче через N часов, синхронно с olcbox).
		rc.Rounds[clientID] = now.Format(time.RFC3339)
		_ = olcKeyRotationSave(rc)
		return
	}
	if last, perr := time.Parse(time.RFC3339, lastStr); perr == nil {
		// Небольшой допуск (5 мин) под расхождение часов сервер↔olcbox.
		if now.Sub(last) < time.Duration(n)*time.Hour-5*time.Minute {
			return // круг ещё не наступил
		}
	}
	// Круг наступил: ротируем СВОБОДНЫЕ инстансы клиента (peers==0). Занятые
	// пропускаем — они дождутся СЛЕДУЮЩЕГО круга (вместе со всеми).
	peers := olcInstancePeerCount()
	changed := false
	skipped := 0
	for i := range cfg.Clients {
		if cfg.Clients[i].ClientID != clientID {
			continue
		}
		for j := range cfg.Clients[i].Locations {
			key := locationKey(cfg.Clients[i].Locations[j])
			if peers[key] > 0 {
				skipped++
				log.Printf("olc-keyrot: skip busy inst=%s peers=%d (defer to next round)", key, peers[key])
				continue
			}
			nk, kerr := randomHex(32)
			if kerr != nil {
				log.Printf("olc-keyrot: genkey failed inst=%s: %v", key, kerr)
				continue
			}
			cfg.Clients[i].Locations[j].Endpoint.Key = nk
			changed = true
			log.Printf("olc-keyrot: rotated key inst=%s client=%s", key, clientID)
		}
		break
	}
	// Продвигаем время круга ВСЕГДА (даже если что-то пропущено): занятые ждут
	// следующего круга через N, не ротируются вне очереди.
	rc.Rounds[clientID] = now.Format(time.RFC3339)
	if changed {
		cfg.Normalize()
		if verr := cfg.Validate(); verr != nil {
			log.Printf("olc-keyrot: validate failed, NOT saving: %v", verr)
			return
		}
		if serr := saveConfig(olcConfigPath, cfg); serr != nil {
			log.Printf("olc-keyrot: save config failed: %v", serr)
			return
		}
		// Reload рестартует ТОЛЬКО инстансы с изменившимся ключом (DeepEqual) и
		// обновляет supervisor.cfg → тело подписки ниже отдаст НОВЫЕ ключи.
		if rerr := supervisor.Reload(context.Background(), cfg); rerr != nil {
			log.Printf("olc-keyrot: reload failed: %v", rerr)
		} else {
			log.Printf("olc-keyrot: client=%s rotated (free instances restarted); %d busy deferred", clientID, skipped)
		}
	}
	if serr := olcKeyRotationSave(rc); serr != nil {
		log.Printf("olc-keyrot: save state failed: %v", serr)
	}
}

// keyRotationHandler — GET (текущее состояние) / PATCH {global_enabled} (глоб.).
func keyRotationHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			writeJSON(w, olcKeyRotationLoad())
		case http.MethodPatch, http.MethodPut, http.MethodPost:
			var in struct {
				GlobalEnabled *bool `json:"global_enabled"`
			}
			if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
				writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			olcKeyRotationMu.Lock()
			rc := olcKeyRotationLoad()
			if in.GlobalEnabled != nil {
				rc.GlobalEnabled = *in.GlobalEnabled
				// При включении глобально — точку отсчёта кругов инициализирует
				// сам планировщик (Rounds пусты → первый круг через N часов).
			}
			err := olcKeyRotationSave(rc)
			olcKeyRotationMu.Unlock()
			if err != nil {
				writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			log.Printf("olc-keyrot: global saved: global_enabled=%t clients=%d", rc.GlobalEnabled, len(rc.Clients))
			writeJSON(w, rc)
		default:
			writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	}
}

// clientKeyRotationHandler — POST /api/clients/:id/key-rotation {enabled}
// (выборочная автосмена ключей этой подписки).
func clientKeyRotationHandler(configPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimPrefix(r.URL.Path, "/api/clients/")
		id = strings.TrimSuffix(id, "/key-rotation")
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
			Enabled *bool `json:"enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		olcKeyRotationMu.Lock()
		rc := olcKeyRotationLoad()
		if rc.Clients == nil {
			rc.Clients = map[string]bool{}
		}
		if in.Enabled != nil {
			if *in.Enabled {
				rc.Clients[id] = true
			} else {
				delete(rc.Clients, id)
				delete(rc.Rounds, id) // сброс отсчёта при выключении
			}
		}
		err := olcKeyRotationSave(rc)
		olcKeyRotationMu.Unlock()
		if err != nil {
			writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		log.Printf("olc-keyrot: client %s saved: enabled=%v", id, in.Enabled != nil && *in.Enabled)
		writeJSON(w, rc)
	}
}

'''
if 'func keyRotationHandler(' in t:
    print("[patch-key-rotation] implementation already present")
elif fn_anchor in t:
    t = t.replace(fn_anchor, fn_block + fn_anchor, 1); changed = True
    print("[patch-key-rotation] added key-rotation implementation")
else:
    print("[patch-key-rotation] WARN: writeJSON anchor not found — skip implementation")

if changed:
    f.write_text(t)
    print("[patch-key-rotation] OK: main.go updated")
else:
    print("[patch-key-rotation] no changes (idempotent)")
PY
