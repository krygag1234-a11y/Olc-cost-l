#!/usr/bin/env bash
# Olc-cost-l backend: монитор подключений к инстансам по device (read-only).
#
# olcrtc-core логирует при подключении: "peer session <sid> opened (peer=<p>
# device=install-<hex>)" / "session <sid> opened (device=install-<hex>)". Этот
# device == тот же hwid, что olcbox шлёт при запросе подписки (persistent
# per-install id). Значит ОДИН allowlist покрывает и подписку, и подключение.
#
# Этот эндпоинт (read-only) парсит journal olcrtc-manager и отдаёт последние
# устройства, подключавшиеся к инстансам, чтобы их было видно и можно было
# добавить в allowlist. Enforcement на уровне подключения (AuthHook olcrtc-core)
# — отдельный шаг (см. docs/ACCESS-CONTROL.md).
#   GET /api/access/connections → {connections:[{device,count,last}]}
# Idempotent. Target: manager main.go. Run after access-control-api.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-access-connections-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Роут (после /api/access/remove) ---
route_anchor = '\thandler.Handle("/api/access/remove", adminAuth(http.HandlerFunc(accessRemoveHandler)))'
route_add = route_anchor + '''
	handler.Handle("/api/access/connections", adminAuth(http.HandlerFunc(accessConnectionsHandler)))'''
if '/api/access/connections' in t:
    print("[patch-access-connections-api] route already present")
elif route_anchor in t:
    t = t.replace(route_anchor, route_add, 1); changed = True
    print("[patch-access-connections-api] registered /api/access/connections")
else:
    print("[patch-access-connections-api] WARN: access/remove route anchor not found — skip route")

# --- 2. Обработчик (перед func writeJSON) ---
fn_anchor = 'func writeJSON(w http.ResponseWriter, v any) {'
fn_block = r'''// olcConnRecord — запись журнала подключений (персистентная, с накоплением ×N).
// Count — РЕАЛЬНЫЕ подключения: считаем ТОЛЬКО "peer connected: device=…"
// (ровно 1 строка на сессию, оба handshake-пути ядра). Раньше считалась ЛЮБАЯ
// device=-строка (session opened / session … opened (device=…) / disconnected)
// → одно подключение давало ×3-4 (жалоба юзера, сессия №18).
// Denied — отклонённые попытки (AuthHook: "conn attempt … allowed=false").
// Kicked — кики ban-watcher'а ядра ("olc-access: kick dev=…" — живая сессия
// сброшена по бану). Прочие строки журнал НЕ считает.
type olcConnRecord struct {
	Device       string `json:"device"`
	ClientID     string `json:"client_id"`
	LocationName string `json:"location_name"`
	RoomID       string `json:"room_id"`
	Transport    string `json:"transport"`
	Count        int    `json:"count"`
	Denied       int    `json:"denied,omitempty"`
	Kicked       int    `json:"kicked,omitempty"`
	First        string `json:"first"`
	Last         string `json:"last"`
	LastDenied   string `json:"last_denied,omitempty"`
	LastKicked   string `json:"last_kicked,omitempty"`
}

var (
	olcConnJournalMu      sync.Mutex
	olcConnJournal        []*olcConnRecord
	olcConnJournalLoaded  bool
	olcConnClearedAt      string            // водяной знак глобальной очистки: строки буфера <= этого времени игнорируются
	olcConnClearedClients = map[string]string{} // per-client водяные знаки очистки
)

const olcConnJournalPath = "/var/lib/olcrtc/access-connections.json"

func olcConnKey(dev, cid, room, tr string) string { return dev + "|" + cid + "|" + room + "|" + tr }

func olcConnJournalLoad() {
	if olcConnJournalLoaded {
		return
	}
	olcConnJournalLoaded = true
	data, err := os.ReadFile(olcConnJournalPath)
	if err != nil {
		return
	}
	// v2: объект с водяными знаками очистки (без них clear=1 «не работал»:
	// журнал мгновенно пересобирался из тех же строк лог-буферов — Урок 60).
	var v2 struct {
		ClearedAt      string            `json:"cleared_at"`
		ClearedClients map[string]string `json:"cleared_clients"`
		Records        []*olcConnRecord  `json:"records"`
	}
	if json.Unmarshal(data, &v2) == nil && (v2.Records != nil || v2.ClearedAt != "" || len(v2.ClearedClients) > 0) {
		olcConnJournal = v2.Records
		olcConnClearedAt = v2.ClearedAt
		if v2.ClearedClients != nil {
			olcConnClearedClients = v2.ClearedClients
		}
		return
	}
	var recs []*olcConnRecord // legacy-формат: плоский массив
	if json.Unmarshal(data, &recs) == nil {
		olcConnJournal = recs
	}
}

func olcConnJournalSave() {
	_ = os.MkdirAll("/var/lib/olcrtc", 0o755)
	obj := map[string]any{"cleared_at": olcConnClearedAt, "cleared_clients": olcConnClearedClients, "records": olcConnJournal}
	if data, err := json.MarshalIndent(obj, "", "  "); err == nil {
		tmp := olcConnJournalPath + ".tmp"
		if os.WriteFile(tmp, append(data, '\n'), 0o600) == nil {
			_ = os.Rename(tmp, olcConnJournalPath)
		}
	}
}

// accessConnectionsHandler: НАКОПИТЕЛЬНЫЙ журнал подключений к инстансам (device=…
// из per-instance лог-буферов) с привязкой клиент/инстанс и счётчиком ×N. Записи
// ПЕРСИСТЯТСЯ в access-connections.json — не пропадают при ротации кольцевого
// буфера и переживают рестарт; повторные подключения увеличивают Count по НОВЫМ
// строкам (без двойного счёта). ?clear=1 очищает журнал. Read-only.
func accessConnectionsHandler(w http.ResponseWriter, r *http.Request) {
	reDevice := regexp.MustCompile(`device=([^\s)]+)`)
	reKick := regexp.MustCompile(`dev=([^\s)]+)`)
	olcConnJournalMu.Lock()
	defer olcConnJournalMu.Unlock()
	olcConnJournalLoad()

	if strings.TrimSpace(r.URL.Query().Get("clear")) == "1" {
		now := time.Now().UTC().Format(time.RFC3339)
		cid := strings.TrimSpace(r.URL.Query().Get("client_id"))
		if cid != "" {
			// очистить только записи этой подписки + водяной знак (строки буфера
			// до этого момента не будут пересчитаны заново)
			kept := olcConnJournal[:0]
			for _, rec := range olcConnJournal {
				if rec.ClientID != cid {
					kept = append(kept, rec)
				}
			}
			olcConnJournal = kept
			olcConnClearedClients[cid] = now
		} else {
			olcConnJournal = nil
			olcConnClearedAt = now
		}
		olcConnJournalSave()
		writeJSON(w, map[string]any{"connections": []any{}})
		return
	}

	index := map[string]*olcConnRecord{}
	for _, rec := range olcConnJournal {
		index[olcConnKey(rec.Device, rec.ClientID, rec.RoomID, rec.Transport)] = rec
	}

	var procs []*process
	if panelSupervisor != nil {
		panelSupervisor.mu.RLock()
		for _, pr := range panelSupervisor.processes {
			procs = append(procs, pr)
		}
		panelSupervisor.mu.RUnlock()
	}
	for _, p := range procs {
		if p == nil || p.logs == nil {
			continue
		}
		cid := p.location.ClientID
		lname := p.location.Name
		room := p.location.Endpoint.RoomID
		tr := p.location.Transport.Type
		for _, ln := range p.logs.Snapshot() {
			// водяные знаки очистки: старые строки буфера не пересчитываем
			if olcConnClearedAt != "" && ln.Time <= olcConnClearedAt {
				continue
			}
			if wm := olcConnClearedClients[cid]; wm != "" && ln.Time <= wm {
				continue
			}
			// классификация: считаем ТОЛЬКО значимые события (см. olcConnRecord)
			kind := ""
			dev := ""
			switch {
			case strings.Contains(ln.Line, "olc-access: conn attempt") && strings.Contains(ln.Line, "allowed=false"):
				kind = "denied"
				if mm := reDevice.FindStringSubmatch(ln.Line); mm != nil {
					dev = mm[1]
				}
			case strings.Contains(ln.Line, "peer connected: device="):
				kind = "accepted"
				if mm := reDevice.FindStringSubmatch(ln.Line); mm != nil {
					dev = mm[1]
				}
			case strings.Contains(ln.Line, "olc-access: kick dev="):
				kind = "kicked"
				if mm := reKick.FindStringSubmatch(ln.Line); mm != nil {
					dev = mm[1]
				}
			}
			if kind == "" || dev == "" {
				continue
			}
			key := olcConnKey(dev, cid, room, tr)
			rec := index[key]
			if rec == nil {
				rec = &olcConnRecord{Device: dev, ClientID: cid, LocationName: lname, RoomID: room, Transport: tr}
				index[key] = rec
				olcConnJournal = append(olcConnJournal, rec)
			}
			if rec.Last == "" || ln.Time > rec.Last {
				switch kind {
				case "denied":
					rec.Denied++
					rec.LastDenied = ln.Time
				case "kicked":
					rec.Kicked++
					rec.LastKicked = ln.Time
				default:
					rec.Count++
				}
				rec.Last = ln.Time
				if rec.First == "" {
					rec.First = ln.Time
				}
				if rec.LocationName == "" {
					rec.LocationName = lname
				}
			}
		}
	}
	if len(olcConnJournal) > 300 {
		sort.SliceStable(olcConnJournal, func(i, j int) bool { return olcConnJournal[i].Last < olcConnJournal[j].Last })
		olcConnJournal = olcConnJournal[len(olcConnJournal)-300:]
	}
	olcConnJournalSave()

	sorted := append([]*olcConnRecord(nil), olcConnJournal...)
	sort.SliceStable(sorted, func(i, j int) bool { return sorted[i].Last < sorted[j].Last })
	list := make([]olcConnRecord, 0, len(sorted))
	for _, rec := range sorted {
		list = append(list, *rec)
	}
	writeJSON(w, map[string]any{"connections": list})
}

'''
if 'func accessConnectionsHandler(' in t:
    print("[patch-access-connections-api] handler already present")
elif fn_anchor in t:
    t = t.replace(fn_anchor, fn_block + fn_anchor, 1); changed = True
    print("[patch-access-connections-api] added accessConnectionsHandler")
else:
    print("[patch-access-connections-api] WARN: writeJSON anchor not found — skip handler")

if changed:
    f.write_text(t)
    print("[patch-access-connections-api] OK: main.go updated")
else:
    print("[patch-access-connections-api] no changes (idempotent)")
PY
