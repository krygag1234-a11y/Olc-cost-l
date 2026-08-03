#!/usr/bin/env bash
# Discover a trusted HTTPS Jitsi hostname for a public numeric IP.
set -euo pipefail

MAIN_GO="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN_GO" ]] || exit 0
grep -q 'olc-jitsi-https-discovery-v1' "$MAIN_GO" && { echo "[patch-jitsi-https-discovery] already applied"; exit 0; }

python3 - "$MAIN_GO" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

route_anchor = '\thandler.Handle("/api/jitsi/preflight", adminAuth(http.HandlerFunc(jitsiPreflightHandler)))\n'
route = route_anchor + '\thandler.Handle("/api/jitsi/discover-https", adminAuth(http.HandlerFunc(jitsiHTTPSDiscoveryHandler)))\n'
if text.count(route_anchor) != 1:
    raise SystemExit("[patch-jitsi-https-discovery] route anchor changed")
text = text.replace(route_anchor, route, 1)

anchor = "// OLC_MANAGER_UPSTREAM_FOLLOWUP_V1"
if text.count(anchor) != 1:
    raise SystemExit("[patch-jitsi-https-discovery] backend insertion anchor changed")

code = r'''/* olc-jitsi-https-discovery-v1 */
type jitsiHTTPSCandidate struct {
	Domain     string   `json:"domain"`
	URL        string   `json:"url"`
	Confidence string   `json:"confidence"`
	Evidence   []string `json:"evidence"`
}

type jitsiHTTPSDiscoveryResponse struct {
	OK         bool                  `json:"ok"`
	SourceIP   string                `json:"source_ip,omitempty"`
	Summary    string                `json:"summary"`
	Candidates []jitsiHTTPSCandidate `json:"candidates"`
	Tried      int                   `json:"tried"`
}

type jitsiDomainProbe struct {
	Jitsi      bool
	ConfigCode int
	RootCode   int
	WSCode     int
	BOSHCode   int
}

func jitsiHTTPSDiscoveryHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	result, status := discoverJitsiHTTPS(r.Context(), strings.TrimSpace(r.URL.Query().Get("server")))
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(result)
}

func publicJitsiIP(raw string) (net.IP, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, errors.New("укажите HTTP/IP Jitsi-сервера")
	}
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Hostname() == "" {
		return nil, errors.New("не удалось разобрать адрес сервера")
	}
	ip := net.ParseIP(u.Hostname())
	if ip == nil {
		return nil, errors.New("помощник запускается только для числового IP")
	}
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() || ip.IsMulticast() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
		return nil, errors.New("для поиска нужен публичный IP")
	}
	return ip, nil
}

func cleanJitsiDomain(value string) string {
	value = strings.ToLower(strings.TrimSpace(strings.TrimSuffix(value, ".")))
	value = strings.TrimPrefix(value, "*.")
	if net.ParseIP(value) != nil || strings.ContainsAny(value, " /@") || !strings.Contains(value, ".") {
		return ""
	}
	for _, label := range strings.Split(value, ".") {
		if label == "" || len(label) > 63 || strings.HasPrefix(label, "-") || strings.HasSuffix(label, "-") {
			return ""
		}
		for _, ch := range label {
			if (ch < 'a' || ch > 'z') && (ch < '0' || ch > '9') && ch != '-' {
				return ""
			}
		}
	}
	return value
}

func directJitsiCertificateNames(ip net.IP) []string {
	dialer := &net.Dialer{Timeout: 4 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", net.JoinHostPort(ip.String(), "443"), &tls.Config{InsecureSkipVerify: true, MinVersion: tls.VersionTLS12})
	if err != nil {
		return nil
	}
	defer conn.Close()
	state := conn.ConnectionState()
	if len(state.PeerCertificates) == 0 {
		return nil
	}
	names := append([]string(nil), state.PeerCertificates[0].DNSNames...)
	if cn := strings.TrimSpace(state.PeerCertificates[0].Subject.CommonName); cn != "" {
		names = append(names, cn)
	}
	return names
}

func jitsiIPHints(ctx context.Context, ip net.IP) map[string][]string {
	hints := map[string][]string{}
	add := func(raw, evidence string) {
		raw = strings.ToLower(strings.TrimSpace(strings.TrimSuffix(raw, ".")))
		wildcard := strings.HasPrefix(raw, "*.")
		base := cleanJitsiDomain(raw)
		if base == "" {
			return
		}
		addOne := func(domain string) {
			domain = cleanJitsiDomain(domain)
			if domain == "" || len(hints) >= 56 {
				return
			}
			for _, old := range hints[domain] {
				if old == evidence {
					return
				}
			}
			hints[domain] = append(hints[domain], evidence)
		}
		if !wildcard {
			addOne(base)
			return
		}
		for _, prefix := range []string{"meet", "jitsi", "conf", "conference", "vc", "video", "call", "calls"} {
			addOne(prefix + "." + base)
		}
	}

	for _, name := range directJitsiCertificateNames(ip) {
		add(name, "имя из TLS-сертификата IP:443")
	}
	lookupCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	if ptrs, err := net.DefaultResolver.LookupAddr(lookupCtx, ip.String()); err == nil {
		for _, ptr := range ptrs {
			add(ptr, "обратная DNS-запись IP")
		}
	}
	cancel()

	tr := &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true, MinVersion: tls.VersionTLS12}}
	client := &http.Client{
		Timeout:   5 * time.Second,
		Transport: tr,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			add(req.URL.Hostname(), "HTTPS/HTTP redirect с исходного IP")
			return http.ErrUseLastResponse
		},
	}
	hintRE := regexp.MustCompile(`(?i)(?:domain|anonymousdomain|authdomain|muc|focus|bosh|websocket)\s*[:=]\s*['"](?:https?:)?(?:/{2})?(?:[^@/'"]+@)?([a-z0-9][a-z0-9.-]+\.[a-z]{2,})(?::[0-9]+)?(?:[/][^'"]*)?['"]`)
	for _, scheme := range []string{"https", "http"} {
		base := scheme + "://" + net.JoinHostPort(ip.String(), map[bool]string{true: "443", false: "80"}[scheme == "https"])
		for _, suffix := range []string{"/", "/config.js"} {
			req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+suffix, nil)
			resp, err := client.Do(req)
			if err != nil {
				continue
			}
			if location := resp.Header.Get("Location"); location != "" {
				if u, parseErr := url.Parse(location); parseErr == nil {
					add(u.Hostname(), "redirect с исходного IP")
				}
			}
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
			_ = resp.Body.Close()
			for _, match := range hintRE.FindAllStringSubmatch(string(body), 24) {
				if len(match) == 2 {
					add(match[1], "Jitsi config.js")
				}
			}
		}
	}
	return hints
}

func resolveDomainToIP(ctx context.Context, domain string, sourceIP net.IP) bool {
	lookupCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	addresses, err := net.DefaultResolver.LookupIPAddr(lookupCtx, domain)
	if err != nil {
		return false
	}
	for _, address := range addresses {
		if address.IP.Equal(sourceIP) {
			return true
		}
	}
	return false
}

func probeJitsiHTTPS(ctx context.Context, domain string, forcedIP net.IP) jitsiDomainProbe {
	dialer := &net.Dialer{Timeout: 4 * time.Second}
	transport := &http.Transport{TLSClientConfig: &tls.Config{ServerName: domain, MinVersion: tls.VersionTLS12}}
	if forcedIP != nil {
		transport.DialContext = func(dialCtx context.Context, network, _ string) (net.Conn, error) {
			return dialer.DialContext(dialCtx, network, net.JoinHostPort(forcedIP.String(), "443"))
		}
	}
	client := &http.Client{
		Timeout:   6 * time.Second,
		Transport: transport,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
	}
	base := "https://" + net.JoinHostPort(domain, "443")
	probe := func(path string, websocket bool) (int, string) {
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+path, nil)
		if websocket {
			req.Header.Set("Connection", "Upgrade")
			req.Header.Set("Upgrade", "websocket")
			req.Header.Set("Sec-WebSocket-Version", "13")
			req.Header.Set("Sec-WebSocket-Key", "SGVsbG9Xb3JsZDEyMzQ=")
		}
		resp, err := client.Do(req)
		if err != nil {
			return 0, ""
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
		_ = resp.Body.Close()
		return resp.StatusCode, strings.ToLower(string(body))
	}

	configCode, configBody := probe("/config.js", false)
	rootCode, rootBody := probe("/", false)
	wsCode, _ := probe("/xmpp-websocket", true)
	boshCode, boshBody := probe("/http-bind", false)
	configMarker := configCode == 200 && (strings.Contains(configBody, "var config") || strings.Contains(configBody, "hosts:") || strings.Contains(configBody, "websocket:") || strings.Contains(configBody, "bosh:"))
	rootMarker := rootCode > 0 && rootCode < 500 && (strings.Contains(rootBody, "jitsi") || strings.Contains(rootBody, "config.js") || strings.Contains(rootBody, "interface_config"))
	boshMarker := boshCode == 200 && (strings.Contains(boshBody, "body") || strings.Contains(boshBody, "xmpp"))
	wsMarker := wsCode == 101 || wsCode == 200 || wsCode == 400 || wsCode == 426 || wsCode == 501
	return jitsiDomainProbe{Jitsi: configMarker || (rootMarker && (boshMarker || wsMarker)), ConfigCode: configCode, RootCode: rootCode, WSCode: wsCode, BOSHCode: boshCode}
}

func verifyJitsiHTTPSCandidate(ctx context.Context, domain string, sourceIP net.IP, sourceEvidence []string) (jitsiHTTPSCandidate, bool) {
	normal := probeJitsiHTTPS(ctx, domain, nil)
	if !normal.Jitsi {
		return jitsiHTTPSCandidate{}, false
	}
	dnsMatch := resolveDomainToIP(ctx, domain, sourceIP)
	forced := jitsiDomainProbe{}
	if dnsMatch {
		forced = normal
	} else {
		forced = probeJitsiHTTPS(ctx, domain, sourceIP)
		if !forced.Jitsi {
			return jitsiHTTPSCandidate{}, false
		}
	}
	evidence := append([]string(nil), sourceEvidence...)
	if dnsMatch {
		evidence = append(evidence, "DNS домена указывает на исходный IP")
	} else {
		evidence = append(evidence, "домен работает обычно и как SNI/vhost на исходном IP")
	}
	evidence = append(evidence, fmt.Sprintf("доверенный TLS; config=%d, ws=%d, bosh=%d", normal.ConfigCode, normal.WSCode, normal.BOSHCode))
	return jitsiHTTPSCandidate{
		Domain:     domain,
		URL:        "https://" + net.JoinHostPort(domain, "443"),
		Confidence: "verified",
		Evidence:   evidence,
	}, true
}

func discoverJitsiHTTPS(parent context.Context, raw string) (jitsiHTTPSDiscoveryResponse, int) {
	out := jitsiHTTPSDiscoveryResponse{Summary: "Проверенный HTTPS-домен не найден", Candidates: []jitsiHTTPSCandidate{}}
	ip, err := publicJitsiIP(raw)
	if err != nil {
		out.Summary = err.Error()
		return out, http.StatusBadRequest
	}
	out.SourceIP = ip.String()
	ctx, cancel := context.WithTimeout(parent, 32*time.Second)
	defer cancel()
	hints := jitsiIPHints(ctx, ip)
	domains := make([]string, 0, len(hints))
	for domain := range hints {
		domains = append(domains, domain)
	}
	sort.Strings(domains)
	out.Tried = len(domains)

	sem := make(chan struct{}, 6)
	var mu sync.Mutex
	var wg sync.WaitGroup
	for _, domain := range domains {
		domain := domain
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				return
			}
			candidate, ok := verifyJitsiHTTPSCandidate(ctx, domain, ip, hints[domain])
			if !ok {
				return
			}
			mu.Lock()
			out.Candidates = append(out.Candidates, candidate)
			mu.Unlock()
		}()
	}
	wg.Wait()
	sort.Slice(out.Candidates, func(i, j int) bool { return out.Candidates[i].Domain < out.Candidates[j].Domain })
	if len(out.Candidates) > 0 {
		out.OK = true
		out.Summary = fmt.Sprintf("Найдено проверенных HTTPS-доменов: %d", len(out.Candidates))
	} else if ctx.Err() != nil {
		out.Summary = "Поиск завершён по таймауту; проверенный HTTPS-домен не найден"
	}
	return out, http.StatusOK
}

'''

text = text.replace(anchor, code + anchor, 1)
path.write_text(text)
print("[patch-jitsi-https-discovery] ok")
PY
