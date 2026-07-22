#!/usr/bin/env bash
# Olc-cost-l backend: контроль доступа к подписке по hwid устройства (v2).
#
# olcbox при запросе подписки шлёт `x-hwid: install-<32hex>` + `User-Agent`.
# Реализовано:
#   - allowlist разрешённых hwid; журнал попыток с ГРУППИРОВКОЙ (Count) вместо спама;
#   - режимы off/monitor/enforce;
#   - ВАЖНО: попытки фиксируются ДАЖЕ при включённой рандомизации, и разрешённое
#     устройство может запрашивать подписку по ОРИГИНАЛЬНОМУ client-id при вкл.
#     рандомизации (для остальных — только рандомизированный id).
#
# Хранение: /var/lib/olcrtc/access-control.json + access-attempts.json (в бэкапе).
# API (adminAuth): GET/PUT /api/access/settings; GET /api/access/attempts;
#   POST /api/access/attempts/clear; POST /api/access/allow|remove {hwid|ip}.
# Idempotent. Target: manager main.go. Run after subscription-randomization.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-access-control-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Роуты (после /api/instance-defaults) ---
route_anchor = '\thandler.Handle("/api/instance-defaults", adminAuth(http.HandlerFunc(instanceDefaultsHandler)))'
route_add = route_anchor + '''
	// Olc-cost-l: контроль доступа к подписке по hwid устройства (allowlist + журнал).
	handler.Handle("/api/access/settings", adminAuth(http.HandlerFunc(accessSettingsHandler)))
	handler.Handle("/api/access/attempts", adminAuth(http.HandlerFunc(accessAttemptsHandler)))
	handler.Handle("/api/access/attempts/clear", adminAuth(http.HandlerFunc(accessAttemptsClearHandler)))
	handler.Handle("/api/access/allow", adminAuth(http.HandlerFunc(accessAllowHandler)))
	handler.Handle("/api/access/device", adminAuth(http.HandlerFunc(accessDeviceHandler)))
	handler.Handle("/api/access/client", adminAuth(http.HandlerFunc(accessClientHandler)))
	handler.Handle("/api/access/remove", adminAuth(http.HandlerFunc(accessRemoveHandler)))'''
if '/api/access/settings' in t:
    print("[patch-access-control-api] routes already present")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1); changed = True
    print("[patch-access-control-api] registered /api/access/* routes")
else:
    print("[patch-access-control-api] WARN: instance-defaults anchor not found — skip routes")

# --- 2. Интеграция контроля доступа в subscriptionHandler (post-randomization) ---
res_anchor = '''		resolvedClientID, err := resolveClientID(requestedID, cfg)
		if err != nil {
			http.NotFound(w, r)
			return
		}'''
res_add = '''		// Контроль доступа по hwid устройства (глобальный + per-client). Попытка
		// фиксируется ВСЕГДА (и при выключенном контроле, и при рандомизации).
		// Бан-лист (устройства/IP/ban_no_hwid) действует в ЛЮБОМ режиме;
		// enforce дополнительно блокирует неизвестных. Allowed в журнале =
		// фактический исход (получил подписку или нет).
		olcAC := olcAccessLoad()
		olcHwid := strings.TrimSpace(r.Header.Get("x-hwid"))
		olcIP := remoteHost(r)
		olcActive, olcAllowedDev, olcDeny, olcMode := olcAccessDecision(olcAC, requestedID, olcHwid, olcIP)
		olcPass := !olcDeny && (olcMode != "enforce" || olcAllowedDev)
		if olcActive {
			olcAccessRecordAttempt(olcAccessAttempt{
				TS: time.Now().UTC().Format(time.RFC3339), HWID: olcHwid, IP: olcIP,
				UA: r.Header.Get("User-Agent"), ClientID: requestedID, Path: r.URL.Path, Allowed: olcPass,
			})
			if !olcPass {
				http.NotFound(w, r)
				return
			}
		}
		// Разрешённое устройство может брать подписку по ОРИГИНАЛЬНОМУ client-id даже
		// при включённой рандомизации; остальным — только рандомизированный id.
		resolvedClientID, err := olcResolveClientIDWithAccess(requestedID, cfg, olcActive && olcAllowedDev && !olcDeny)
		if err != nil {
			http.NotFound(w, r)
			return
		}'''
if 'olcResolveClientIDWithAccess(' in t:
    print("[patch-access-control-api] handler integration already present")
elif res_anchor in t:
    t = t.replace(res_anchor, res_add, 1); changed = True
    print("[patch-access-control-api] integrated access control into subscriptionHandler")
else:
    print("[patch-access-control-api] WARN: resolveClientID anchor not found — skip handler (нужен subscription-randomization)")

# --- 3. Реализация (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// ============================================================================
// Olc-cost-l: контроль доступа к подписке по hwid устройства.
// olcbox шлёт x-hwid (стабильный per-install id) + User-Agent при запросе подписки.
// allowlist разрешённых hwid + журнал попыток (с группировкой/Count). Хранение —
// отдельные JSON-файлы (в бэкапе). См. docs/ACCESS-CONTROL.md.
// !!! ПРИ ИЗМЕНЕНИИ формата — учтите бэкап (backupExtraFiles), UI и API.
// ============================================================================

const olcAccessControlPath = "/var/lib/olcrtc/access-control.json"
const olcAccessAttemptsPath = "/var/lib/olcrtc/access-attempts.json"
const olcAccessAttemptsMax = 200

var olcAccessMu sync.Mutex

// olcAllowedDevice: запись allowlist. Enabled=false — доступ временно отключён, но
// запись сохраняется (можно вернуть). Label — понятное имя («я», «друг»).
type olcAllowedDevice struct {
	HWID    string `json:"hwid"`
	Label   string `json:"label,omitempty"`
	Enabled bool   `json:"enabled"`
}

// olcAllowedIP: разрешённый IP с флагом включения (галочка в UI, как у устройств).
// СОВМЕСТИМОСТЬ: в JSON принимает и legacy-строку ("1.2.3.4" → enabled=true),
// и объект {ip, enabled} — существующие конфиги читаются без миграции.
type olcAllowedIP struct {
	IP      string `json:"ip"`
	Enabled bool   `json:"enabled"`
}

func (a *olcAllowedIP) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		a.IP = strings.TrimSpace(s)
		a.Enabled = true
		return nil
	}
	type olcAllowedIPAlias olcAllowedIP
	var v olcAllowedIPAlias
	if err := json.Unmarshal(data, &v); err != nil {
		return err
	}
	v.IP = strings.TrimSpace(v.IP)
	*a = olcAllowedIP(v)
	return nil
}

// olcClientAccess: индивидуальный контроль доступа для ОДНОЙ подписки (клиента).
// Mode: "inherit" (как глобально) | "off" | "monitor" | "enforce". Allow — доп.
// разрешённые для этой подписки; Ban — забаненные (блок независимо от allow).
// ConnEnforce/ConnScope/ConnInstances — ВЫБОРОЧНЫЙ контроль ПОДКЛЮЧЕНИЯ этой
// подписки (действует, только когда глобальный enforce_connections ВЫКЛЮЧЕН):
// ConnScope "all" (все инстансы) | "selective" (только room_id из ConnInstances).
type olcClientAccess struct {
	Mode          string             `json:"mode"`
	Allow         []olcAllowedDevice `json:"allow"`
	Ban           []olcAllowedDevice `json:"ban"`
	AllowIPs      []olcAllowedIP     `json:"allow_ips,omitempty"`      // разрешённые IP ТОЛЬКО для этой подписки (галочка = вкл/выкл)
	BanIPs        []olcAllowedIP     `json:"ban_ips,omitempty"`        // забаненные IP этой подписки — действуют ВСЕГДА (и в «Выключено»)
	BanNoHwid     bool               `json:"ban_no_hwid"`              // блок запросов без hwid для этой подписки
	ConnAllow     []olcAllowedDevice `json:"conn_allow"`               // разрешённые устройства ПОДКЛЮЧЕНИЯ этой подписки (ОТДЕЛЬНО)
	ConnBan       []olcAllowedDevice `json:"conn_ban"`                 // забаненные устройства ПОДКЛЮЧЕНИЯ этой подписки (ОТДЕЛЬНО)
	ConnEnforce   bool               `json:"conn_enforce"`
	ConnMode      string             `json:"conn_mode,omitempty"` // Olc-cost-l 🔌 off|keyrand|enforce
	ConnScope     string             `json:"conn_scope"`             // "all" | "selective"
	ConnInstances []string           `json:"conn_instances,omitempty"` // room_id инстансов при selective
}

type olcAccessControl struct {
	Enabled      bool                        `json:"enabled"`
	Mode         string                      `json:"mode"` // "monitor" | "enforce"
	Devices      []olcAllowedDevice          `json:"devices"`
	Ban          []olcAllowedDevice          `json:"ban"`               // глобальный бан (по hwid)
	BanNoHwid    bool                        `json:"ban_no_hwid"`       // блокировать запросы без hwid (Compatibility)
	EnforceConns bool                        `json:"enforce_connections"` // энфорсить на УРОВНЕ ПОДКЛЮЧЕНИЯ (AuthHook); default off
	ConnDevices  []olcAllowedDevice          `json:"conn_devices"`      // разрешённые устройства ПОДКЛЮЧЕНИЯ (ОТДЕЛЬНО от devices)
	ConnBan      []olcAllowedDevice          `json:"conn_ban"`          // забаненные устройства ПОДКЛЮЧЕНИЯ (ОТДЕЛЬНО от ban)
	ConnScope     string   `json:"conn_scope,omitempty"`     // ГЛОБАЛЬНЫЙ scope контроля подключения: "all" (пусто=all) | "selective"
	ConnMode      string   `json:"conn_mode,omitempty"`     // Olc-cost-l 🔌 глоб: off|keyrand|enforce (при вкл рандомизации)
	ConnInstances []string `json:"conn_instances,omitempty"` // room_id инстансов при selective (по ВСЕМ клиентам); вайтлист: невыбранный инстанс не пускает никого
	Clients      map[string]*olcClientAccess `json:"clients,omitempty"` // per-подписка
	AllowedHWIDs []string                    `json:"allowed_hwids,omitempty"` // legacy, мигрируется
	AllowedIPs   []olcAllowedIP              `json:"allowed_ips,omitempty"`
	BanIPs       []olcAllowedIP              `json:"ban_ips,omitempty"` // забаненные IP (подписка) — действуют ВСЕГДА (и в «Выключено»)
	UpdatedAt    string                      `json:"updated_at,omitempty"`
}

type olcAccessAttempt struct {
	TS       string `json:"ts"`       // последняя попытка
	FirstTS  string `json:"first_ts"` // первая попытка (для группировки)
	HWID     string `json:"hwid"`
	IP       string `json:"ip"`
	UA       string `json:"ua"`
	ClientID string `json:"client_id"`
	Path     string `json:"path"`
	Allowed  bool   `json:"allowed"`
	Count    int    `json:"count"` // сколько раз это устройство запрашивало (без спама)
}

func olcAccessLoad() olcAccessControl {
	ac := olcAccessControl{Enabled: false, Mode: "monitor", Devices: []olcAllowedDevice{}, AllowedIPs: []olcAllowedIP{}}
	if data, err := os.ReadFile(olcAccessControlPath); err == nil {
		_ = json.Unmarshal(data, &ac)
	}
	if ac.Mode != "enforce" {
		ac.Mode = "monitor"
	}
	if ac.Devices == nil {
		ac.Devices = []olcAllowedDevice{}
	}
	if ac.Ban == nil {
		ac.Ban = []olcAllowedDevice{}
	}
	if ac.ConnDevices == nil {
		ac.ConnDevices = []olcAllowedDevice{}
	}
	if ac.ConnBan == nil {
		ac.ConnBan = []olcAllowedDevice{}
	}
	// миграция legacy allowed_hwids -> devices (каждый включён)
	if len(ac.Devices) == 0 && len(ac.AllowedHWIDs) > 0 {
		for _, h := range ac.AllowedHWIDs {
			if strings.TrimSpace(h) != "" {
				ac.Devices = append(ac.Devices, olcAllowedDevice{HWID: strings.TrimSpace(h), Enabled: true})
			}
		}
	}
	ac.AllowedHWIDs = nil
	if ac.AllowedIPs == nil {
		ac.AllowedIPs = []olcAllowedIP{}
	}
	if ac.BanIPs == nil {
		ac.BanIPs = []olcAllowedIP{}
	}
	if ac.Clients == nil {
		ac.Clients = map[string]*olcClientAccess{}
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

// olcAccessRecordAttempt: группирует по (hwid, client_id) — не спамит журнал
// повторами, а увеличивает Count и обновляет время последней попытки.
func olcAccessRecordAttempt(a olcAccessAttempt) {
	olcAccessMu.Lock()
	defer olcAccessMu.Unlock()
	list := olcAccessLoadAttempts()
	key := strings.ToLower(a.HWID) + "|" + a.ClientID
	for i := range list {
		if strings.ToLower(list[i].HWID)+"|"+list[i].ClientID == key {
			list[i].Count++
			list[i].TS = a.TS
			list[i].IP = a.IP
			list[i].UA = a.UA
			list[i].Allowed = a.Allowed
			list[i].Path = a.Path
			// переместить в конец (самое свежее — внизу)
			item := list[i]
			list = append(list[:i], list[i+1:]...)
			list = append(list, item)
			_olcAccessWriteAttempts(list)
			return
		}
	}
	a.Count = 1
	a.FirstTS = a.TS
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

// olcAccessDecision: сводит глобальный + per-client контроль в решение для запроса
// подписки клиента clientID устройством hwid/ip.
//   active — всегда true (журнал попыток ведётся ВСЕГДА — редизайн UX сессии №17);
//   allowed — устройство разрешено (глоб. devices / per-client allow / allow-IP);
//   deny — жёсткий бан (ban / ban_ips / ban_no_hwid) — блокирует В ЛЮБОМ режиме,
//          в т.ч. «Выключено» (бан-лист действует всегда);
//   mode — эффективный режим: "monitor" (= «Выключено»: пускать всех, кроме
//          бан-листа, лог) | "enforce" («Блокировать неизвестных»).
// ГЛОБАЛЬНЫЙ контроль (enabled) использует ТОЛЬКО глобальные списки; когда он
// выключен — работает ВЫБОРОЧНЫЙ per-client (clients[clientID]) со своими
// списками. Взаимоисключающе (как в UI: при вкл. глобальном шестерёнка недоступна).
// СЕМАНТИКА (сессия №17): режимы off/monitor per-client СЛИТЫ в «Выключено»
// (= monitor-поведение); отсутствующая per-client запись = «Выключено» с пустыми
// списками (лог всё равно пишется).
func olcAccessDecision(ac olcAccessControl, clientID, hwid, ip string) (active bool, allowed bool, deny bool, mode string) {
	var banNoHwid bool
	var bans, allows []olcAllowedDevice
	var allowIPs, banIPs []olcAllowedIP
	if ac.Enabled {
		mode = "monitor"
		if ac.Mode == "enforce" {
			mode = "enforce"
		}
		banNoHwid = ac.BanNoHwid
		bans, allows = ac.Ban, ac.Devices
		allowIPs, banIPs = ac.AllowedIPs, ac.BanIPs
	} else {
		var cc *olcClientAccess
		if ac.Clients != nil {
			cc = ac.Clients[clientID]
		}
		mode = "monitor" // «Выключено»: пускать всех (кроме бан-листа), лог
		if cc != nil {
			if cc.Mode == "enforce" {
				mode = "enforce"
			}
			banNoHwid = cc.BanNoHwid
			bans, allows = cc.Ban, cc.Allow
			allowIPs, banIPs = cc.AllowIPs, cc.BanIPs
		}
	}
	active = true
	hw := strings.TrimSpace(hwid)
	ipt := strings.TrimSpace(ip)
	if hw == "" && banNoHwid {
		return true, false, true, mode
	}
	for _, b := range bans {
		if b.Enabled && strings.TrimSpace(b.HWID) != "" && strings.EqualFold(strings.TrimSpace(b.HWID), hw) {
			return true, false, true, mode
		}
	}
	for _, bip := range banIPs {
		if bip.Enabled && bip.IP != "" && strings.TrimSpace(bip.IP) == ipt {
			return true, false, true, mode
		}
	}
	for _, a := range allows {
		if a.Enabled && strings.TrimSpace(a.HWID) != "" && strings.EqualFold(strings.TrimSpace(a.HWID), hw) {
			return true, true, false, mode
		}
	}
	for _, aip := range allowIPs {
		if aip.Enabled && aip.IP != "" && strings.TrimSpace(aip.IP) == ipt {
			return true, true, false, mode
		}
	}
	return true, false, false, mode
}

func olcAccessAllowed(ac olcAccessControl, hwid, ip string) bool {
	for _, d := range ac.Devices {
		if d.Enabled && d.HWID != "" && strings.EqualFold(strings.TrimSpace(d.HWID), strings.TrimSpace(hwid)) {
			return true
		}
	}
	for _, a := range ac.AllowedIPs {
		if a.Enabled && a.IP != "" && strings.TrimSpace(a.IP) == strings.TrimSpace(ip) {
			return true
		}
	}
	return false
}

// olcResolveClientIDWithAccess: разрешённому устройству (bypass) позволяет брать
// подписку по ОРИГИНАЛЬНОМУ client-id даже при включённой рандомизации; иначе —
// обычный resolveClientID (рандомизированный id / 404 для оригинала под рандомом).
func olcResolveClientIDWithAccess(requestedID string, cfg Config, bypass bool) (string, error) {
	if bypass {
		for _, client := range cfg.Clients {
			if client.ClientID == requestedID {
				return requestedID, nil
			}
		}
	}
	return resolveClientID(requestedID, cfg)
}

func accessSettingsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, olcAccessLoad())
	case http.MethodPut, http.MethodPost:
		// ЧАСТИЧНОЕ обновление: применяются ТОЛЬКО присланные поля (nil = не трогать).
		// Раньше PUT заменял булевы/списки телом целиком → сохранение со stale
		// state молча затирало параллельные изменения.
		var in struct {
			Enabled      *bool              `json:"enabled"`
			Mode         *string            `json:"mode"`
			Devices      []olcAllowedDevice `json:"devices"`
			Ban          []olcAllowedDevice `json:"ban"`
			BanNoHwid    *bool              `json:"ban_no_hwid"`
			EnforceConns *bool              `json:"enforce_connections"`
			ConnDevices  []olcAllowedDevice `json:"conn_devices"`
			ConnBan      []olcAllowedDevice `json:"conn_ban"`
			ConnScope     *string           `json:"conn_scope"`
			ConnMode      *string           `json:"conn_mode"`
			ConnInstances []string          `json:"conn_instances"`
			AllowedIPs   []olcAllowedIP     `json:"allowed_ips"`
			BanIPs       []olcAllowedIP     `json:"ban_ips"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		cur := olcAccessLoad()
		if in.Enabled != nil {
			cur.Enabled = *in.Enabled
		}
		if in.Mode != nil && (*in.Mode == "enforce" || *in.Mode == "monitor" || *in.Mode == "keyrand") {
			cur.Mode = *in.Mode
		}
		if in.Devices != nil {
			cur.Devices = olcAccessNormalizeDevices(in.Devices)
		}
		if in.Ban != nil {
			cur.Ban = olcAccessNormalizeDevices(in.Ban)
		}
		if in.BanNoHwid != nil {
			cur.BanNoHwid = *in.BanNoHwid
		}
		if in.EnforceConns != nil {
			cur.EnforceConns = *in.EnforceConns
		}
		if in.ConnDevices != nil {
			cur.ConnDevices = olcAccessNormalizeDevices(in.ConnDevices)
		}
		if in.ConnBan != nil {
			cur.ConnBan = olcAccessNormalizeDevices(in.ConnBan)
		}
		if in.ConnScope != nil {
			s := *in.ConnScope
			if s != "selective" {
				s = "all"
			}
			cur.ConnScope = s
		}
		if in.ConnMode != nil {
			m := *in.ConnMode
			if m != "keyrand" && m != "enforce" {
				m = "off"
			}
			cur.ConnMode = m
		}
		if in.ConnInstances != nil {
			cur.ConnInstances = olcAccessDedup(in.ConnInstances)
		}
		if in.AllowedIPs != nil {
			cur.AllowedIPs = olcAccessDedupIPs(in.AllowedIPs)
		}
		if in.BanIPs != nil {
			cur.BanIPs = olcAccessDedupIPs(in.BanIPs)
		}
		log.Printf("olc-access: global saved: enabled=%t mode=%s devices=%d ban=%d ips=%d ban_ips=%d enforce_conns=%t conn_devices=%d conn_ban=%d scope=%s insts=%d", cur.Enabled, cur.Mode, len(cur.Devices), len(cur.Ban), len(cur.AllowedIPs), len(cur.BanIPs), cur.EnforceConns, len(cur.ConnDevices), len(cur.ConnBan), cur.ConnScope, len(cur.ConnInstances))
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
	cid := strings.TrimSpace(r.URL.Query().Get("client_id"))
	if cid != "" {
		// очистить только записи конкретной подписки
		kept := []olcAccessAttempt{}
		for _, a := range olcAccessLoadAttempts() {
			if a.ClientID != cid {
				kept = append(kept, a)
			}
		}
		_olcAccessWriteAttempts(kept)
	} else {
		_olcAccessWriteAttempts([]olcAccessAttempt{})
	}
	olcAccessMu.Unlock()
	writeJSON(w, map[string]any{"status": "ok"})
}

func accessAllowHandler(w http.ResponseWriter, r *http.Request) {
	var body struct {
		HWID  string `json:"hwid"`
		Label string `json:"label"`
		IP    string `json:"ip"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	ac := olcAccessLoad()
	if h := strings.TrimSpace(body.HWID); h != "" {
		ac.Devices = olcAccessUpsertDevice(ac.Devices, olcAllowedDevice{HWID: h, Label: strings.TrimSpace(body.Label), Enabled: true})
	}
	if ip := strings.TrimSpace(body.IP); ip != "" {
		ac.AllowedIPs = olcAccessDedupIPs(append(ac.AllowedIPs, olcAllowedIP{IP: ip, Enabled: true}))
	}
	if err := olcAccessSave(ac); err != nil {
		writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, ac)
}

// accessDeviceHandler: обновить запись устройства — переименовать (label) и/или
// включить/выключить (enabled), НЕ теряя из allowlist. POST {hwid, label?, enabled}.
func accessDeviceHandler(w http.ResponseWriter, r *http.Request) {
	var body struct {
		HWID    string `json:"hwid"`
		Label   *string `json:"label"`
		Enabled *bool   `json:"enabled"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	h := strings.TrimSpace(body.HWID)
	if h == "" {
		writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "hwid required"})
		return
	}
	ac := olcAccessLoad()
	found := false
	for i := range ac.Devices {
		if strings.EqualFold(strings.TrimSpace(ac.Devices[i].HWID), h) {
			if body.Label != nil {
				ac.Devices[i].Label = strings.TrimSpace(*body.Label)
			}
			if body.Enabled != nil {
				ac.Devices[i].Enabled = *body.Enabled
			}
			found = true
			break
		}
	}
	if !found {
		d := olcAllowedDevice{HWID: h, Enabled: true}
		if body.Label != nil {
			d.Label = strings.TrimSpace(*body.Label)
		}
		if body.Enabled != nil {
			d.Enabled = *body.Enabled
		}
		ac.Devices = append(ac.Devices, d)
	}
	if err := olcAccessSave(ac); err != nil {
		writeJSONStatus(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, ac)
}

// accessClientHandler: индивидуальный контроль доступа для подписки.
//   GET  /api/access/client?client_id=ID → текущая per-client конфигурация;
//   POST /api/access/client {client_id, mode?, allow?[], ban?[]} → сохранить;
//     mode="inherit" (или пустой allow+ban) удаляет per-client override.
func accessClientHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		id := strings.TrimSpace(r.URL.Query().Get("client_id"))
		ac := olcAccessLoad()
		if cc, ok := ac.Clients[id]; ok && cc != nil {
			writeJSON(w, cc)
			return
		}
		writeJSON(w, olcClientAccess{Mode: "inherit", Allow: []olcAllowedDevice{}, Ban: []olcAllowedDevice{}, AllowIPs: []olcAllowedIP{}, BanIPs: []olcAllowedIP{}, ConnAllow: []olcAllowedDevice{}, ConnBan: []olcAllowedDevice{}, ConnScope: "all", ConnInstances: []string{}})
		return
	}
	if r.Method != http.MethodPost && r.Method != http.MethodPut {
		writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	// ЧАСТИЧНОЕ обновление (как в settings): применяются ТОЛЬКО присланные поля.
	// Раньше POST заменял ВСЮ запись телом запроса — любое сохранение со stale
	// state UI молча стирало параллельные изменения (у юзера так слетел conn_ban
	// через 6с после бана). nil-слайс = поле не прислано = не трогать; [] = очистить.
	var body struct {
		ClientID      string             `json:"client_id"`
		Mode          *string            `json:"mode"`
		Allow         []olcAllowedDevice `json:"allow"`
		Ban           []olcAllowedDevice `json:"ban"`
		AllowIPs      []olcAllowedIP     `json:"allow_ips"`
		BanIPs        []olcAllowedIP     `json:"ban_ips"`
		BanNoHwid     *bool              `json:"ban_no_hwid"`
		ConnAllow     []olcAllowedDevice `json:"conn_allow"`
		ConnBan       []olcAllowedDevice `json:"conn_ban"`
		ConnEnforce   *bool              `json:"conn_enforce"`
		ConnScope     *string            `json:"conn_scope"`
		ConnMode      *string            `json:"conn_mode"`
		ConnInstances []string           `json:"conn_instances"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	id := strings.TrimSpace(body.ClientID)
	if id == "" {
		writeJSONStatus(w, http.StatusBadRequest, map[string]string{"error": "client_id required"})
		return
	}
	ac := olcAccessLoad()
	cc := ac.Clients[id]
	if cc == nil {
		cc = &olcClientAccess{Mode: "off", Allow: []olcAllowedDevice{}, Ban: []olcAllowedDevice{}, AllowIPs: []olcAllowedIP{}, BanIPs: []olcAllowedIP{}, ConnAllow: []olcAllowedDevice{}, ConnBan: []olcAllowedDevice{}, ConnScope: "all", ConnInstances: []string{}}
	}
	if body.Mode != nil && (*body.Mode == "off" || *body.Mode == "monitor" || *body.Mode == "enforce" || *body.Mode == "keyrand") {
		cc.Mode = *body.Mode
	}
	if body.Allow != nil {
		cc.Allow = olcAccessNormalizeDevices(body.Allow)
	}
	if body.Ban != nil {
		cc.Ban = olcAccessNormalizeDevices(body.Ban)
	}
	if body.AllowIPs != nil {
		cc.AllowIPs = olcAccessDedupIPs(body.AllowIPs)
	}
	if body.BanIPs != nil {
		cc.BanIPs = olcAccessDedupIPs(body.BanIPs)
	}
	if body.BanNoHwid != nil {
		cc.BanNoHwid = *body.BanNoHwid
	}
	if body.ConnAllow != nil {
		cc.ConnAllow = olcAccessNormalizeDevices(body.ConnAllow)
	}
	if body.ConnBan != nil {
		cc.ConnBan = olcAccessNormalizeDevices(body.ConnBan)
	}
	if body.ConnEnforce != nil {
		cc.ConnEnforce = *body.ConnEnforce
	}
	if body.ConnScope != nil {
		s := *body.ConnScope
		if s != "selective" {
			s = "all"
		}
		cc.ConnScope = s
	}
	if body.ConnMode != nil {
		m := *body.ConnMode
		if m != "keyrand" && m != "enforce" {
			m = "off"
		}
		cc.ConnMode = m
	}
	if body.ConnInstances != nil {
		cc.ConnInstances = olcAccessDedup(body.ConnInstances)
	}
	if cc.Allow == nil {
		cc.Allow = []olcAllowedDevice{}
	}
	if cc.Ban == nil {
		cc.Ban = []olcAllowedDevice{}
	}
	if cc.AllowIPs == nil {
		cc.AllowIPs = []olcAllowedIP{}
	}
	if cc.BanIPs == nil {
		cc.BanIPs = []olcAllowedIP{}
	}
	if cc.ConnAllow == nil {
		cc.ConnAllow = []olcAllowedDevice{}
	}
	if cc.ConnBan == nil {
		cc.ConnBan = []olcAllowedDevice{}
	}
	if cc.ConnInstances == nil {
		cc.ConnInstances = []string{}
	}
	if cc.ConnScope == "" {
		cc.ConnScope = "all"
	}
	ac.Clients[id] = cc
	log.Printf("olc-access: client %s saved: mode=%s allow=%d ban=%d allow_ips=%d ban_ips=%d conn_allow=%d conn_ban=%d conn_enforce=%t scope=%s insts=%d", id, cc.Mode, len(cc.Allow), len(cc.Ban), len(cc.AllowIPs), len(cc.BanIPs), len(cc.ConnAllow), len(cc.ConnBan), cc.ConnEnforce, cc.ConnScope, len(cc.ConnInstances))
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
		next := ac.Devices[:0]
		for _, d := range ac.Devices {
			if !strings.EqualFold(strings.TrimSpace(d.HWID), h) {
				next = append(next, d)
			}
		}
		ac.Devices = next
	}
	if ip := strings.TrimSpace(body.IP); ip != "" {
		next := ac.AllowedIPs[:0]
		for _, x := range ac.AllowedIPs {
			if strings.TrimSpace(x.IP) != ip {
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

// olcAccessUpsertDevice: добавить/обновить устройство по hwid (не дублируя).
func olcAccessUpsertDevice(list []olcAllowedDevice, d olcAllowedDevice) []olcAllowedDevice {
	for i := range list {
		if strings.EqualFold(strings.TrimSpace(list[i].HWID), strings.TrimSpace(d.HWID)) {
			list[i].Enabled = true
			if d.Label != "" {
				list[i].Label = d.Label
			}
			return list
		}
	}
	return append(list, d)
}

// olcAccessNormalizeDevices: тримминг + дедуп по hwid.
func olcAccessNormalizeDevices(in []olcAllowedDevice) []olcAllowedDevice {
	seen := map[string]bool{}
	out := []olcAllowedDevice{}
	for _, d := range in {
		h := strings.TrimSpace(d.HWID)
		if h == "" || seen[strings.ToLower(h)] {
			continue
		}
		seen[strings.ToLower(h)] = true
		out = append(out, olcAllowedDevice{HWID: h, Label: strings.TrimSpace(d.Label), Enabled: d.Enabled})
	}
	return out
}

func olcAccessDedupIPs(in []olcAllowedIP) []olcAllowedIP {
	seen := map[string]bool{}
	out := []olcAllowedIP{}
	for _, x := range in {
		v := strings.TrimSpace(x.IP)
		if v == "" || seen[strings.ToLower(v)] {
			continue
		}
		seen[strings.ToLower(v)] = true
		out = append(out, olcAllowedIP{IP: v, Enabled: x.Enabled})
	}
	return out
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
if 'func olcResolveClientIDWithAccess(' in t:
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
