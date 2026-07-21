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
	// Olc-cost-l: автосмена ключей (Z5-B) — глобальная настройка.
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

# --- 3. Старт планировщика (после определения reload) ---
sched_anchor = '''		return supervisor.Reload(ctx, reloaded)
	}
'''
sched_add = '''		return supervisor.Reload(ctx, reloaded)
	}
	// Olc-cost-l: планировщик автосмены ключей (Z5-B). Инертен, пока не включён.
	go olcKeyRotationLoop(configPath, reload)
'''
if 'go olcKeyRotationLoop(configPath, reload)' in t:
    print("[patch-key-rotation] scheduler start already present")
elif sched_anchor in t:
    t = t.replace(sched_anchor, sched_add, 1); changed = True
    print("[patch-key-rotation] started olcKeyRotationLoop goroutine")
else:
    print("[patch-key-rotation] WARN: reload closure anchor not found — scheduler NOT started")

# --- 4. Реализация (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// ============================================================================
// Olc-cost-l: «♻️ Автосмена ключей» (Z5-B). Периодическая перегенерация
// ОРИГИНАЛЬНОГО ключа шифрования инстансов. Состояние — отдельный файл
// /var/lib/olcrtc/key-rotation.json (Config не трогаем). Ротация ждёт peers=0
// на инстансе (занятые — до следующего круга). См. хендофф Задача №5.
// ============================================================================

const olcKeyRotationPath = "/var/lib/olcrtc/key-rotation.json"

var olcKeyRotationMu sync.Mutex

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

// olcKeyRotationLoop — фоновый планировщик. Тик раз в минуту; фактическая
// ротация клиента происходит не чаще раза в N часов (интервал автообновления).
func olcKeyRotationLoop(configPath string, reload func() error) {
	time.Sleep(30 * time.Second) // дать инстансам подняться после старта
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		func() {
			defer func() {
				if r := recover(); r != nil {
					log.Printf("olc-keyrot: panic recovered: %v", r)
				}
			}()
			olcKeyRotationTick(configPath, reload)
		}()
	}
}

func olcKeyRotationTick(configPath string, reload func() error) {
	olcKeyRotationMu.Lock()
	defer olcKeyRotationMu.Unlock()

	rc := olcKeyRotationLoad()
	if !rc.GlobalEnabled && len(rc.Clients) == 0 {
		return // ничего не включено — инертно
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		log.Printf("olc-keyrot: load config failed: %v", err)
		return
	}
	cfg.ensureClientsFormat()
	peers := olcInstancePeerCount()
	now := time.Now().UTC()
	changed := false
	roundsChanged := false

	for i := range cfg.Clients {
		cid := cfg.Clients[i].ClientID
		if !olcKeyRotationEnabledFor(rc, cid) {
			continue
		}
		n := subscriptionRefreshHours(cfg, cid)
		if n <= 0 {
			n = 24 // дефолт olcbox
		}
		lastStr := rc.Rounds[cid]
		if lastStr == "" {
			// Первое наблюдение клиента под ротацией: фиксируем точку отсчёта,
			// НЕ ротируя сразу (первый круг — через N часов).
			rc.Rounds[cid] = now.Format(time.RFC3339)
			roundsChanged = true
			continue
		}
		last, perr := time.Parse(time.RFC3339, lastStr)
		if perr == nil && now.Sub(last) < time.Duration(n)*time.Hour {
			continue // круг ещё не наступил
		}
		// Круг наступил: ротируем СВОБОДНЫЕ инстансы (peers==0). Занятые
		// пропускаем — они дождутся СЛЕДУЮЩЕГО круга (вместе со всеми).
		skipped := 0
		for j := range cfg.Clients[i].Locations {
			loc := cfg.Clients[i].Locations[j]
			key := locationKey(loc)
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
			log.Printf("olc-keyrot: rotated key inst=%s client=%s", key, cid)
		}
		// Продвигаем время круга ВСЕГДА (даже если что-то пропущено): занятые
		// ждут следующего круга через N часов, не ротируются вне очереди.
		rc.Rounds[cid] = now.Format(time.RFC3339)
		roundsChanged = true
		if skipped > 0 {
			log.Printf("olc-keyrot: client=%s round done, %d busy instance(s) deferred", cid, skipped)
		}
	}

	if changed {
		cfg.Normalize()
		if verr := cfg.Validate(); verr != nil {
			log.Printf("olc-keyrot: validate failed, NOT saving: %v", verr)
			return
		}
		if serr := saveConfig(configPath, cfg); serr != nil {
			log.Printf("olc-keyrot: save config failed: %v", serr)
			return
		}
		if rerr := reload(); rerr != nil {
			log.Printf("olc-keyrot: reload failed: %v", rerr)
		} else {
			log.Printf("olc-keyrot: config saved + reloaded (rotated instances restarted)")
		}
	}
	if roundsChanged {
		if serr := olcKeyRotationSave(rc); serr != nil {
			log.Printf("olc-keyrot: save state failed: %v", serr)
		}
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
