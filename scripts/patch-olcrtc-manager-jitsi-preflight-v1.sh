#!/usr/bin/env bash
# Add GET /api/jitsi/preflight for Jitsi room diagnostics.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-jitsi-preflight-v1' "$MAIN_GO" && { echo "[patch-jitsi-preflight-v1] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

route = '\thandler.Handle("/api/jitsi/preflight", adminAuth(http.HandlerFunc(jitsiPreflightHandler)))\n'
anchor = '\thandler.Handle("/api/features", adminAuth(http.HandlerFunc(featuresListHandler())))'
if '"/api/jitsi/preflight"' not in t and anchor in t:
    t = t.replace(anchor, route + anchor, 1)

imports = t.split("import (", 1)[1].split(")", 1)[0]
for imp, needle in (
    ('"crypto/tls"', '"crypto/subtle"\n'),
    ('"io"', '"hash/fnv"\n'),
    ('"regexp"', '"reflect"\n'),
):
    if imp not in imports and needle in t:
        t = t.replace(needle, needle + "\t" + imp + "\n", 1)

helpers = r'''
/* olc-jitsi-preflight-v1 */
type jitsiPreflightResponse struct {
	OK      bool     `json:"ok"`
	Code    string   `json:"code"`
	Summary string   `json:"summary"`
	Details []string `json:"details"`
	Host    string   `json:"host,omitempty"`
	Room    string   `json:"room,omitempty"`
	WSURL   string   `json:"ws_url,omitempty"`
	WSCode  int      `json:"ws_status,omitempty"`
	BOSHURL string   `json:"bosh_url,omitempty"`
	BOSHCode int     `json:"bosh_status,omitempty"`
}

func jitsiPreflightHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	roomID := strings.TrimSpace(r.URL.Query().Get("room_id"))
	writeJSON(w, preflightJitsiRoom(roomID))
}

func preflightJitsiRoom(roomID string) jitsiPreflightResponse {
	out := jitsiPreflightResponse{
		OK:      false,
		Code:    "invalid",
		Summary: "Некорректный room id",
		Details: []string{"Укажите ссылку вида https://host/room"},
	}
	raw := strings.TrimSpace(roomID)
	if raw == "" {
		return out
	}
	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || strings.TrimSpace(u.Host) == "" {
		out.Details = []string{"Не удалось разобрать URL комнаты"}
		return out
	}
	room := strings.Trim(strings.TrimSpace(u.Path), "/")
	if room == "" {
		out.Code = "invalid-room"
		out.Summary = "Для Jitsi нужен URL с названием комнаты"
		out.Details = []string{"Пример: https://meet.example.org/my-room"}
		return out
	}
	out.Host = u.Host
	out.Room = room

	tr := &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}
	client := &http.Client{Timeout: 10 * time.Second, Transport: tr}

	base := u.Scheme + "://" + u.Host
	configJS := ""
	if resp, err := client.Get(base + "/config.js"); err == nil {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
		_ = resp.Body.Close()
		configJS = string(b)
	}
	reWS := regexp.MustCompile(`websocket:\s*['"]([^'"]+)['"]`)
	reBOSH := regexp.MustCompile(`bosh:\s*['"]([^'"]+)['"]`)
	wsURL := ""
	boshURL := ""
	if m := reWS.FindStringSubmatch(configJS); len(m) == 2 {
		wsURL = strings.TrimSpace(m[1])
	}
	if m := reBOSH.FindStringSubmatch(configJS); len(m) == 2 {
		boshURL = strings.TrimSpace(m[1])
	}
	resolve := func(v string) string {
		v = strings.TrimSpace(v)
		switch {
		case v == "":
			return ""
		case strings.HasPrefix(v, "http://") || strings.HasPrefix(v, "https://") || strings.HasPrefix(v, "ws://") || strings.HasPrefix(v, "wss://"):
			return v
		case strings.HasPrefix(v, "//"):
			return "https:" + v
		case strings.HasPrefix(v, "/"):
			return base + v
		default:
			return base + "/" + strings.TrimPrefix(v, "/")
		}
	}
	if wsURL == "" {
		wsURL = base + "/xmpp-websocket"
	} else {
		wsURL = resolve(wsURL)
	}
	if boshURL == "" {
		boshURL = base + "/http-bind"
	} else {
		boshURL = resolve(boshURL)
	}
	out.WSURL = wsURL
	out.BOSHURL = boshURL

	probe := func(target string, ws bool) int {
		req, _ := http.NewRequest(http.MethodGet, target, nil)
		if ws {
			req.Header.Set("Connection", "Upgrade")
			req.Header.Set("Upgrade", "websocket")
			req.Header.Set("Sec-WebSocket-Version", "13")
			req.Header.Set("Sec-WebSocket-Key", "SGVsbG9Xb3JsZDEyMzQ=")
		}
		resp, err := client.Do(req)
		if err != nil {
			return 0
		}
		_ = resp.Body.Close()
		return resp.StatusCode
	}

	wsCode := probe(wsURL, true)
	boshCode := probe(boshURL, false)
	out.WSCode = wsCode
	out.BOSHCode = boshCode

	pageHasJWT := false
	if resp, err := client.Get(raw); err == nil {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
		_ = resp.Body.Close()
		s := strings.ToLower(string(b))
		if strings.Contains(s, "tokenauthurl") || (strings.Contains(s, "jwt") && strings.Contains(s, "token")) {
			pageHasJWT = true
		}
	}

	if wsCode == 404 || wsCode == 501 {
		out.Code = "jitsi-websocket-404"
		out.Summary = "Jitsi WebSocket endpoint не принимает upgrade (404/501)"
		out.Details = []string{
			"Хост, вероятно, с кастомным или неполным Jitsi-конфигом",
			"UI в браузере может открываться, но бот не сможет зайти",
			"Рекомендуется другой Jitsi-хост или настройка /xmpp-websocket на стороне сервера",
		}
		return out
	}
	if pageHasJWT {
		out.Code = "jitsi-token-possible"
		out.Summary = "Похоже, хост использует token/JWT авторизацию"
		out.Details = []string{
			"Анонимный вход может быть отключен",
			"Если в runtime логе будет token required — этот room не подходит для olcrtc без токена",
		}
		return out
	}
	if wsCode == 101 || wsCode == 200 || wsCode == 426 {
		out.OK = true
		out.Code = "ok"
		out.Summary = "Базовая Jitsi-проверка пройдена"
		out.Details = []string{"Endpoint отвечает; итоговый join зависит от политики комнаты и jingle"}
		return out
	}
	out.Code = "jitsi-unknown"
	out.Summary = "Неполная проверка Jitsi"
	out.Details = []string{
		fmt.Sprintf("ws=%d bosh=%d", wsCode, boshCode),
		"Проверьте runtime-лог после фактического старта инстанса",
	}
	return out
}
'''

if "func jitsiPreflightHandler(" not in t:
    t = t.rstrip() + "\n\n" + helpers + "\n"

p.write_text(t)
print("[patch-jitsi-preflight-v1] ok")
PY

