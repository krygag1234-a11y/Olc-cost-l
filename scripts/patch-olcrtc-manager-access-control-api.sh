#!/usr/bin/env bash
# Olc-cost-l backend: контроль доступа к подписке по hwid (устройству).
#
# olcbox при запросе подписки шлёт заголовок `x-hwid: install-<32hex>` (стабильный
# per-install идентификатор устройства) + `User-Agent: olcbox/<version>`. Это
# позволяет реально ограничить доступ (в отличие от «рандомизации пути», которую
# можно обойти, просто зная путь):
#   - allowlist разрешённых hwid: известное устройство получает подписку, чужое — 404;
#   - журнал попыток неизвестных hwid (для быстрого добавления в allowlist);
#   - режимы off / monitor (только лог, пускать всех) / enforce (блокировать чужих).
#
# Хранение — отдельные файлы (без правки patched-структур), попадают в бэкап:
#   /var/lib/olcrtc/access-control.json   — {enabled,mode,allowed_hwids,allowed_ips}
#   /var/lib/olcrtc/access-attempts.json  — кольцевой журнал последних попыток
#
# API (adminAuth): GET/PUT /api/access/settings; GET /api/access/attempts;
#   POST /api/access/allow {hwid}; POST /api/access/remove {hwid};
#   POST /api/access/attempts/clear.
#
# ВАЖНО: доступ к ПОДКЛЮЧЕНИЮ к инстансу практически покрывается этим же шлюзом —
# без подписки клиент не получает room_id/key, значит не подключится. Enforcement
# на самом WebRTC-уровне потребовал бы патча pinned-upstream olcrtc-core.
# Idempotent. Target: manager main.go. Run after golden-panel copy.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-access-control-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Роуты (после /api/instance-defaults; backup-патч мог добавить свои рядом) ---
route_anchor = '\thandler.Handle("/api/instance-defaults", adminAuth(http.HandlerFunc(instanceDefaultsHandler)))'
route_add = route_anchor + '''
	// Olc-cost-l: контроль доступа к подписке по hwid устройства (allowlist + журнал).
	handler.Handle("/api/access/settings", adminAuth(http.HandlerFunc(accessSettingsHandler)))
	handler.Handle("/api/access/attempts", adminAuth(http.HandlerFunc(accessAttemptsHandler)))
	handler.Handle("/api/access/attempts/clear", adminAuth(http.HandlerFunc(accessAttemptsClearHandler)))
	handler.Handle("/api/access/allow", adminAuth(http.HandlerFunc(accessAllowHandler)))
	handler.Handle("/api/access/remove", adminAuth(http.HandlerFunc(accessRemoveHandler)))'''
if '/api/access/settings' in t:
    print("[patch-access-control-api] routes already present")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1); changed = True
    print("[patch-access-control-api] registered /api/access/* routes")
else:
    print("[patch-access-control-api] WARN: instance-defaults anchor not found — skip routes")

# --- 2. Шлюз в subscriptionHandler ---
gate_anchor = '''		sub, ok := supervisor.SubscriptionForClient(clientID, time.Now())
		if !ok {
			http.NotFound(w, r)
			return
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")'''
gate_add = '''		sub, ok := supervisor.SubscriptionForClient(clientID, time.Now())
		if !ok {
			http.NotFound(w, r)
			return
		}

		// Контроль доступа по hwid устройства (olcbox шлёт x-hwid). Записывает
		// попытку и, в режиме enforce, блокирует неизвестные устройства (404).
		if !olcAccessGate(w, r, clientID) {
			return
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")'''
if 'olcAccessGate(' in t:
    print("[patch-access-control-api] gate already present")
elif gate_anchor in t:
    t = t.replace(gate_anchor, gate_add, 1); changed = True
    print("[patch-access-control-api] added subscription hwid gate")
else:
    print("[patch-access-control-api] WARN: subscription handler anchor not found — skip gate")

# --- 3. Реализация (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// ============================================================================
// Olc-cost-l: контроль доступа к подписке по hwid устройства.
// olcbox шлёт заголовок x-hwid (стабильный per-install id) + User-Agent при
// запросе подписки. allowlist разрешённых hwid + журнал попыток неизвестных.
// Хранение — отдельные JSON-файлы (в бэкапе). См. docs/ACCESS-CONTROL.md.
// !!! ПРИ ИЗМЕНЕНИИ формата — учтите бэкап (backupExtraFiles) и UI.
// ============================================================================

const olcAccessControlPath = "/var/lib/olcrtc/access-control.json"
const olcAccessAttemptsPath = "/var/lib/olcrtc/access-attempts.json"
const olcAccessAttemptsMax = 200

var olcAccessMu sync.Mutex

type olcAccessControl struct {
	Enabled      bool     `json:"enabled"`
	Mode         string   `json:"mode"` // "monitor" (лог, пускать) | "enforce" (блокировать чужих)
	AllowedHWIDs []string `json:"allowed_hwids"`
	AllowedIPs   []string `json:"allowed_ips,omitempty"`
	UpdatedAt    string   `json:"updated_at,omitempty"`
}

type olcAccessAttempt struct {
	TS       string `json:"ts"`
	HWID     string `json:"hwid"`
	IP       string `json:"ip"`
	UA       string `json:"ua"`
	ClientID string `json:"client_id"`
	Path     string `json:"path"`
	Allowed  bool   `json:"allowed"`
}

func olcAccessLoad() olcAccessControl {
	ac := olcAccessControl{Enabled: false, Mode: "monitor", AllowedHWIDs: []string{}, AllowedIPs: []string{}}
	if data, err := os.ReadFile(olcAccessControlPath); err == nil {
		_ = json.Unmarshal(data, &ac)
	}
	if ac.Mode != "enforce" {
		ac.Mode = "monitor"
	}
	if ac.AllowedHWIDs == nil {
		ac.AllowedHWIDs = []string{}
	}
	if ac.AllowedIPs == nil {
		ac.AllowedIPs = []string{}
	}
	return ac
}

func olcAccessSave(ac olcAccessControl) error {
	ac.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	if err := os.MkdirAll(filepath.Dir(olcAccessControlPath), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(ac, "", "  ")
	if err != nil {
		return err
	}
	tmp := olcAccessControlPath + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, olcAccessControlPath)
}

func olcAccessLoadAttempts() []olcAccessAttempt {
	var out struct {
		Attempts []olcAccessAttempt `json:"attempts"`
	}
	if data, err := os.ReadFile(olcAccessAttemptsPath); err == nil {
		_ = json.Unmarshal(data, &out)
	}
	if out.Attempts == nil {
		out.Attempts = []olcAccessAttempt{}
	}
	return out.Attempts
}

func olcAccessRecordAttempt(a olcAccessAttempt) {
	olcAccessMu.Lock()
	defer olcAccessMu.Unlock()
	list := olcAccessLoadAttempts()
	// дедуп: если самая свежая запись — тот же hwid+client и та же «разрешённость»,
	// просто обновим время (не засоряем журнал повторами автообновлений подписки).
	if len(list) > 0 {
		last := list[len(list)-1]
		if last.HWID == a.HWID && last.ClientID == a.ClientID && last.Allowed == a.Allowed {
			list[len(list)-1].TS = a.TS
			list[len(list)-1].IP = a.IP
			list[len(list)-1].UA = a.UA
			_olcAccessWriteAttempts(list)
			return
		}
	}
	list = append(list, a)
	if len(list) > olcAccessAttemptsMax {
		list = list[len(list)-olcAccessAttemptsMax:]
	}
	_olcAccessWriteAttempts(list)
}

func _olcAccessWriteAttempts(list []olcAccessAttempt) {
	_ = os.MkdirAll(filepath.Dir(olcAccessAttemptsPath), 0o755)
	data, err := json.MarshalIndent(map[string]any{"attempts": list}, "", "  ")
	if err != nil {
		return
	}
	tmp := olcAccessAttemptsPath + ".tmp"
	if os.WriteFile(tmp, append(data, '\n'), 0o600) == nil {
		_ = os.Rename(tmp, olcAccessAttemptsPath)
	}
}

func olcAccessAllowed(ac olcAccessControl, hwid, ip string) bool {
	for _, h := range ac.AllowedHWIDs {
		if h != "" && strings.EqualFold(strings.TrimSpace(h), strings.TrimSpace(hwid)) {
			return true
		}
	}
	for _, a := range ac.AllowedIPs {
		if a != "" && strings.TrimSpace(a) == strings.TrimSpace(ip) {
			return true
		}
	}
	return false
}

// olcAccessGate: записывает попытку и решает, отдавать ли подписку. Возвращает
// false (и пишет 404) только в режиме enforce для неизвестного устройства.
func olcAccessGate(w http.ResponseWriter, r *http.Request, clientID string) bool {
	ac := olcAccessLoad()
	if !ac.Enabled {
		return true
	}
	hwid := strings.TrimSpace(r.Header.Get("x-hwid"))
	ip := remoteHost(r)
	ua := r.Header.Get("User-Agent")
	allowed := olcAccessAllowed(ac, hwid, ip)
	olcAccessRecordAttempt(olcAccessAttempt{
		TS: time.Now().UTC().Format(time.RFC3339), HWID: hwid, IP: ip, UA: ua,
		ClientID: clientID, Path: r.URL.Path, Allowed: allowed,
	})
	if ac.Mode == "enforce" && !allowed {
		http.NotFound(w, r) // не раскрываем существование пути неизвестному устройству
		return false
	}
	return true
}

func accessSettingsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, olcAccessLoad())
	case http.MethodPut, http.MethodPost:
		var in olcAccessControl
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		cur := olcAccessLoad()
		cur.Enabled = in.Enabled
		if in.Mode == "enforce" || in.Mode == "monitor" {
			cur.Mode = in.Mode
		}
		if in.AllowedHWIDs != nil {
			cur.AllowedHWIDs = olcAccessDedup(in.AllowedHWIDs)
		}
		if in.AllowedIPs != nil {
			cur.AllowedIPs = olcAccessDedup(in.AllowedIPs)
		}
		if err := olcAccessSave(cur); err != nil {
			writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, cur)
	default:
		writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

func accessAttemptsHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{"attempts": olcAccessLoadAttempts()})
}

func accessAttemptsClearHandler(w http.ResponseWriter, r *http.Request) {
	olcAccessMu.Lock()
	_olcAccessWriteAttempts([]olcAccessAttempt{})
	olcAccessMu.Unlock()
	writeJSON(w, map[string]any{"status": "ok"})
}

func accessAllowHandler(w http.ResponseWriter, r *http.Request) {
	var body struct {
		HWID string `json:"hwid"`
		IP   string `json:"ip"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	ac := olcAccessLoad()
	if h := strings.TrimSpace(body.HWID); h != "" {
		ac.AllowedHWIDs = olcAccessDedup(append(ac.AllowedHWIDs, h))
	}
	if ip := strings.TrimSpace(body.IP); ip != "" {
		ac.AllowedIPs = olcAccessDedup(append(ac.AllowedIPs, ip))
	}
	if err := olcAccessSave(ac); err != nil {
		writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, ac)
}

func accessRemoveHandler(w http.ResponseWriter, r *http.Request) {
	var body struct {
		HWID string `json:"hwid"`
		IP   string `json:"ip"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	ac := olcAccessLoad()
	if h := strings.TrimSpace(body.HWID); h != "" {
		next := ac.AllowedHWIDs[:0]
		for _, x := range ac.AllowedHWIDs {
			if !strings.EqualFold(strings.TrimSpace(x), h) {
				next = append(next, x)
			}
		}
		ac.AllowedHWIDs = next
	}
	if ip := strings.TrimSpace(body.IP); ip != "" {
		next := ac.AllowedIPs[:0]
		for _, x := range ac.AllowedIPs {
			if strings.TrimSpace(x) != ip {
				next = append(next, x)
			}
		}
		ac.AllowedIPs = next
	}
	if err := olcAccessSave(ac); err != nil {
		writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, ac)
}

func olcAccessDedup(in []string) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, s := range in {
		s = strings.TrimSpace(s)
		if s == "" || seen[strings.ToLower(s)] {
			continue
		}
		seen[strings.ToLower(s)] = true
		out = append(out, s)
	}
	return out
}

'''
if 'func olcAccessGate(' in t:
    print("[patch-access-control-api] impl already present")
elif fn_anchor in t:
    t = t.replace(fn_anchor, fn_block + fn_anchor, 1); changed = True
    print("[patch-access-control-api] added access-control impl")
else:
    print("[patch-access-control-api] WARN: writeJSON anchor not found — skip impl")

if changed:
    f.write_text(t)
    print("[patch-access-control-api] OK: main.go updated")
else:
    print("[patch-access-control-api] no changes (idempotent)")
PY
