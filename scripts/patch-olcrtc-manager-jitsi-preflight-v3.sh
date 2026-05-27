#!/usr/bin/env bash
# Jitsi preflight: treat WS 501 + BOSH 200 as non-fatal.
set -euo pipefail
MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-jitsi-preflight-v3' "$MAIN_GO" && { echo "[patch-jitsi-preflight-v3] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()
fn = "func preflightJitsiRoom(roomID string) jitsiPreflightResponse {"
start = t.find(fn)
if start < 0:
    print("[patch-jitsi-preflight-v3] skip (preflight not found)")
    sys.exit(0)

brace = t.find("{", start)
depth = 0
end = -1
for i in range(brace, len(t)):
    if t[i] == "{":
        depth += 1
    elif t[i] == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end < 0:
    raise SystemExit("[patch-jitsi-preflight-v3] function end not found")

new_fn = r'''func preflightJitsiRoom(roomID string) jitsiPreflightResponse {
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
	if resp, e := client.Get(base + "/config.js"); e == nil {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
		_ = resp.Body.Close()
		configJS = string(b)
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
	reWS := regexp.MustCompile(`websocket:\s*['"]([^'"]+)['"]`)
	altWS := ""
	if m := reWS.FindStringSubmatch(configJS); len(m) == 2 {
		altWS = resolve(m[1])
	}
	mainWS := base + "/xmpp-websocket"
	reBOSH := regexp.MustCompile(`bosh:\s*['"]([^'"]+)['"]`)
	boshURL := base + "/http-bind"
	if m := reBOSH.FindStringSubmatch(configJS); len(m) == 2 {
		boshURL = resolve(m[1])
	}

	out.WSURL = mainWS
	if altWS != "" && altWS != mainWS {
		out.WSURL = mainWS + " | alt: " + altWS
	}
	out.BOSHURL = boshURL

	probe := func(target string, ws bool) int {
		req, _ := http.NewRequest(http.MethodGet, target, nil)
		if ws {
			req.Header.Set("Connection", "Upgrade")
			req.Header.Set("Upgrade", "websocket")
			req.Header.Set("Sec-WebSocket-Version", "13")
			req.Header.Set("Sec-WebSocket-Key", "SGVsbG9Xb3JsZDEyMzQ=")
		}
		resp, e := client.Do(req)
		if e != nil {
			return 0
		}
		_ = resp.Body.Close()
		return resp.StatusCode
	}

	mainWSCode := probe(mainWS, true)
	altWSCode := 0
	if altWS != "" && altWS != mainWS {
		altWSCode = probe(altWS, true)
	}
	boshCode := probe(boshURL, false)
	out.WSCode = mainWSCode
	out.BOSHCode = boshCode

	if mainWSCode == 404 {
		if altWSCode == 101 || altWSCode == 200 || altWSCode == 426 {
			out.OK = true
			out.Code = "ok-alt-websocket"
			out.Summary = "Стандартный /xmpp-websocket не отвечает, но альтернативный endpoint живой"
			out.Details = []string{fmt.Sprintf("/xmpp-websocket=%d, alt=%d", mainWSCode, altWSCode)}
			return out
		}
		out.Code = "jitsi-websocket-404"
		out.Summary = "Jitsi WebSocket endpoint не найден (404)"
		out.Details = []string{
			fmt.Sprintf("/xmpp-websocket=%d", mainWSCode),
			"Для этого хоста runtime join обычно падает на xmpp dial / websocket handshake",
		}
		return out
	}

	// Important: many self-hosted Jitsi return 501 on websocket upgrade,
	// but still support BOSH (/http-bind) and can work in runtime.
	if mainWSCode == 501 && boshCode == 200 {
		out.OK = true
		out.Code = "ok-bosh-only"
		out.Summary = "WebSocket upgrade (501), но BOSH доступен — хост потенциально рабочий"
		out.Details = []string{
			fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode),
			"Проверяйте финальный статус по runtime-логу (join/token/jingle), а не только по preflight",
		}
		return out
	}

	if mainWSCode == 101 || mainWSCode == 200 || mainWSCode == 426 {
		out.OK = true
		out.Code = "ok"
		out.Summary = "Базовая Jitsi-проверка пройдена"
		out.Details = []string{fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode)}
		return out
	}

	out.OK = true
	out.Code = "weak-signal"
	out.Summary = "Предпроверка не нашла явного блокера, но результат не окончательный"
	out.Details = []string{
		fmt.Sprintf("/xmpp-websocket=%d, bosh=%d", mainWSCode, boshCode),
		"Финальный статус определяется runtime-логом jitsi join",
	}
	return out
}'''

t = t[:start] + new_fn + t[end:]
if "olc-jitsi-preflight-v3" not in t:
    t = t.replace("/* olc-jitsi-preflight-v2 */", "/* olc-jitsi-preflight-v2 */\n/* olc-jitsi-preflight-v3 */", 1)

p.write_text(t)
print("[patch-jitsi-preflight-v3] ok")
PY

