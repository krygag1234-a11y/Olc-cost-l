#!/usr/bin/env python3
from pathlib import Path
import sys
MARKER="OLC_PROXY_POLICY_V1"

def one(s, old, new, label):
    n=s.count(old)
    if n!=1: raise SystemExit(f"{label}: expected 1, got {n}")
    return s.replace(old,new,1)

def patch_go(path):
    s=path.read_text()
    if MARKER in s: return
    s=one(s, '''type Client struct {
	ClientID      string               `json:"client-id"`
	Refresh       string               `json:"refresh,omitempty"`
	Quota         Quota                `json:"quota,omitempty"`
	Locations     []Location           `json:"locations"`
	Randomization *ClientRandomization `json:"randomization,omitempty"`
}''', '''type Client struct {
	ClientID      string               `json:"client-id"`
	Refresh       string               `json:"refresh,omitempty"`
	Quota         Quota                `json:"quota,omitempty"`
	Proxy         Socks5Proxy          `json:"proxy,omitempty"`
	Locations     []Location           `json:"locations"`
	Randomization *ClientRandomization `json:"randomization,omitempty"`
}''','client proxy')
    s=one(s, '''type Socks5Proxy struct {
	Addr string `json:"addr,omitempty"`
	Port int    `json:"port,omitempty"`
	User string `json:"user,omitempty"`
	Pass string `json:"pass,omitempty"`
}''', '''type Socks5Proxy struct {
	Enabled *bool  `json:"enabled,omitempty"`
	Addr    string `json:"addr,omitempty"`
	Port    int    `json:"port,omitempty"`
	User    string `json:"user,omitempty"`
	Pass    string `json:"pass,omitempty"`
	Routing string `json:"routing,omitempty"` // split (default) | all
}''','proxy policy fields')
    s=one(s, '''type ClientState struct {
	ClientID      string               `json:"client_id"`
	Refresh       string               `json:"refresh,omitempty"`
	Quota         Quota                `json:"quota"`
	Locations     []LocationState      `json:"locations"`
	Randomization *ClientRandomization `json:"randomization,omitempty"`
}''', '''type ClientState struct {
	ClientID      string               `json:"client_id"`
	Refresh       string               `json:"refresh,omitempty"`
	Quota         Quota                `json:"quota"`
	Proxy         Socks5Proxy          `json:"proxy,omitempty"`
	Locations     []LocationState      `json:"locations"`
	Randomization *ClientRandomization `json:"randomization,omitempty"`
}''','client state proxy')
    s=one(s, '''	Quota      Quota             `json:"quota"`
	Locations  []locationRequest `json:"locations"`''','''	Quota      Quota             `json:"quota"`
	ClientProxy Socks5Proxy       `json:"client_proxy"`
	Locations  []locationRequest `json:"locations"`''','add request client proxy')
    s=one(s, '''	Quota     Quota             `json:"quota"`
	Locations []locationRequest `json:"locations"`''','''	Quota     Quota             `json:"quota"`
	ClientProxy Socks5Proxy       `json:"client_proxy"`
	Locations []locationRequest `json:"locations"`''','update request client proxy')
    s=one(s, '''cfg.Clients = append(cfg.Clients, Client{ClientID: req.ClientID, Refresh: req.Refresh, Quota: req.Quota, Locations: locations})''','''req.ClientProxy = normalizeProxy(req.ClientProxy)
	if err := validateProxy(req.ClientProxy); err != nil {
		return "", fmt.Errorf("client_proxy: %w", err)
	}
	cfg.Clients = append(cfg.Clients, Client{ClientID: req.ClientID, Refresh: req.Refresh, Quota: req.Quota, Proxy: req.ClientProxy, Locations: locations})''','create client proxy')
    s=one(s, '''		cfg.Clients[i].Refresh = req.Refresh
		cfg.Clients[i].Quota = req.Quota
		if locations != nil {''','''		cfg.Clients[i].Refresh = req.Refresh
		cfg.Clients[i].Quota = req.Quota
		req.ClientProxy = normalizeProxy(req.ClientProxy)
		if err := validateProxy(req.ClientProxy); err != nil {
			return fmt.Errorf("client_proxy: %w", err)
		}
		cfg.Clients[i].Proxy = req.ClientProxy
		if locations != nil {''','update client proxy')
    s=one(s, '''func normalizeProxy(proxy Socks5Proxy) Socks5Proxy {
	proxy.Addr = strings.TrimSpace(proxy.Addr)
	proxy.User = strings.TrimSpace(proxy.User)
	return proxy
}

func validateProxy(proxy Socks5Proxy) error {''', '''func normalizeProxy(proxy Socks5Proxy) Socks5Proxy {
	proxy.Addr = strings.TrimSpace(proxy.Addr)
	proxy.User = strings.TrimSpace(proxy.User)
	proxy.Routing = strings.ToLower(strings.TrimSpace(proxy.Routing))
	if proxy.Routing == "" && (proxy.Enabled != nil || proxy.Addr != "") {
		proxy.Routing = "split"
	}
	return proxy
}

func proxyEnabled(proxy Socks5Proxy) bool {
	if proxy.Enabled != nil {
		return *proxy.Enabled
	}
	return proxy.Addr != "" // legacy configs: a filled proxy was implicitly enabled
}

func boolPointer(v bool) *bool { return &v }

func validateProxy(proxy Socks5Proxy) error {''','proxy helpers')
    s=one(s, '''func validateProxy(proxy Socks5Proxy) error {
	if proxy.Addr == "" {''', '''func validateProxy(proxy Socks5Proxy) error {
	if proxy.Routing != "" && proxy.Routing != "split" && proxy.Routing != "all" {
		return errors.New("routing must be split or all")
	}
	if proxyEnabled(proxy) && proxy.Addr == "" {
		return errors.New("addr is required when proxy is enabled")
	}
	if proxy.Addr == "" {''','proxy validate policy')
    s=one(s, '''	for i := range c.Clients {
		c.Clients[i].Refresh = strings.TrimSpace(c.Clients[i].Refresh)
	}''', '''	for i := range c.Clients {
		c.Clients[i].Refresh = strings.TrimSpace(c.Clients[i].Refresh)
		c.Clients[i].Proxy = normalizeProxy(c.Clients[i].Proxy)
	}''','normalize client proxy')
    s=one(s, '''		if err := validateQuota(client.Quota); err != nil {
			return fmt.Errorf("clients[%d].quota: %w", i, err)
		}
''', '''		if err := validateQuota(client.Quota); err != nil {
			return fmt.Errorf("clients[%d].quota: %w", i, err)
		}
		if err := validateProxy(client.Proxy); err != nil {
			return fmt.Errorf("clients[%d].proxy: %w", i, err)
		}
''','validate client proxy')
    # State carries saved client proxy, never the resolved global override.
    s=one(s, '''		var randomization *ClientRandomization
		for _, client := range s.cfg.Clients {''','''		var randomization *ClientRandomization
		clientProxy := Socks5Proxy{}
		for _, client := range s.cfg.Clients {''','state proxy temp')
    s=one(s, '''				refresh = client.Refresh
				randomization = client.Randomization''','''				refresh = client.Refresh
				clientProxy = client.Proxy
				randomization = client.Randomization''','state proxy assign')
    s=one(s, '''			Quota:         quota,
			Locations:     clients[id],''','''			Quota:         quota,
			Proxy:         clientProxy,
			Locations:     clients[id],''','state proxy output')
    # Global settings persistence in panel.env.
    s=one(s, '''		"OLCRTC_SOCKS_PROXY":         true,
''', '''		"OLCRTC_SOCKS_PROXY":         true,
		"OLCRTC_GLOBAL_SOCKS_ENABLED": true,
		"OLCRTC_GLOBAL_SOCKS_ADDR":    true,
		"OLCRTC_GLOBAL_SOCKS_PORT":    true,
		"OLCRTC_GLOBAL_SOCKS_USER":    true,
		"OLCRTC_GLOBAL_SOCKS_PASS":    true,
		"OLCRTC_GLOBAL_SOCKS_ROUTING": true,
''','global env allow')
    s=one(s, '''		"socks_proxy":         env["OLCRTC_SOCKS_PROXY"],
''', '''		"socks_proxy":         env["OLCRTC_SOCKS_PROXY"], // legacy display-only field
		"global_socks_enabled": env["OLCRTC_GLOBAL_SOCKS_ENABLED"] == "1",
		"global_socks_addr":    env["OLCRTC_GLOBAL_SOCKS_ADDR"],
		"global_socks_port":    env["OLCRTC_GLOBAL_SOCKS_PORT"],
		"global_socks_user":    env["OLCRTC_GLOBAL_SOCKS_USER"],
		"global_socks_pass":    env["OLCRTC_GLOBAL_SOCKS_PASS"],
		"global_socks_routing": defaultString(env["OLCRTC_GLOBAL_SOCKS_ROUTING"], "split"),
''','global settings get')
    s=one(s, '''	if v, ok := body["socks_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_SOCKS_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
''', '''	if v, ok := body["socks_proxy"].(string); ok {
		if err := setPanelEnvKey("OLCRTC_SOCKS_PROXY", strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	globalProxyKeys := map[string]string{
		"global_socks_addr": "OLCRTC_GLOBAL_SOCKS_ADDR", "global_socks_port": "OLCRTC_GLOBAL_SOCKS_PORT",
		"global_socks_user": "OLCRTC_GLOBAL_SOCKS_USER", "global_socks_pass": "OLCRTC_GLOBAL_SOCKS_PASS",
		"global_socks_routing": "OLCRTC_GLOBAL_SOCKS_ROUTING",
	}
	for bodyKey, envKey := range globalProxyKeys {
		if v, ok := body[bodyKey].(string); ok {
			if err := setPanelEnvKey(envKey, strings.TrimSpace(v)); err != nil { return err }
		}
	}
	if v, ok := body["global_socks_enabled"].(bool); ok {
		value := "0"; if v { value = "1" }
		if err := setPanelEnvKey("OLCRTC_GLOBAL_SOCKS_ENABLED", value); err != nil { return err }
	}
''','global settings put')
    # Resolution helpers inserted before activeLocations.
    anchor='''func activeLocations(cfg Config, now time.Time) []Location {'''
    helpers='''func globalProxyPolicy() Socks5Proxy {
	env := readPanelEnvMap()
	enabled := env["OLCRTC_GLOBAL_SOCKS_ENABLED"] == "1"
	port, _ := strconv.Atoi(strings.TrimSpace(env["OLCRTC_GLOBAL_SOCKS_PORT"]))
	return normalizeProxy(Socks5Proxy{Enabled: boolPointer(enabled), Addr: env["OLCRTC_GLOBAL_SOCKS_ADDR"], Port: port, User: env["OLCRTC_GLOBAL_SOCKS_USER"], Pass: env["OLCRTC_GLOBAL_SOCKS_PASS"], Routing: env["OLCRTC_GLOBAL_SOCKS_ROUTING"]})
}

func effectiveProxyPolicyWithGlobal(global Socks5Proxy, cfg Config, loc Location) (Socks5Proxy, string) {
	if proxyEnabled(global) { return normalizeProxy(global), "global" }
	for _, client := range cfg.Clients {
		if client.ClientID == loc.ClientID && proxyEnabled(client.Proxy) {
			return normalizeProxy(client.Proxy), "client"
		}
	}
	if proxyEnabled(loc.Proxy) { return normalizeProxy(loc.Proxy), "instance" }
	return Socks5Proxy{}, "automatic"
}

func effectiveProxyPolicy(cfg Config, loc Location) (Socks5Proxy, string) {
	return effectiveProxyPolicyWithGlobal(globalProxyPolicy(), cfg, loc)
}

func applyProxyRouting(cfg *olcrtcRuntimeConfig, routing string) {
	if strings.EqualFold(strings.TrimSpace(routing), "all") { return }
	flags := readFeatureFlags()
	if flags["split"] || flags["zapret"] {
		cfg.SOCKS.DirectCIDRsFile = directCIDRsFileFromEnv()
		cfg.SOCKS.DirectDomainsFile = directDomainsFileFromEnv()
		cfg.SOCKS.BlockedTorDomainsFile = blockedTorDomainsFileFromEnv()
		cfg.SOCKS.ForceTorDomainsFile = forceTorDomainsFileFromEnv()
	}
}

'''
    s=one(s,anchor,helpers+anchor,'proxy resolution helpers')
    s=one(s, '''		out = append(out, loc)
''', '''		loc.Proxy, _ = effectiveProxyPolicy(cfg, loc)
		out = append(out, loc)
''','resolve active location')
    # serverConfig: explicit custom retains split lists by default; automatic uses same helper.
    old='''	// Если в Location задан явный Proxy — используем его
	if loc.Proxy.Addr != "" {
		cfg.SOCKS = olcrtcSocksConfig{
			ProxyAddr: loc.Proxy.Addr,
			ProxyPort: loc.Proxy.Port,
			ProxyUser: loc.Proxy.User,
			ProxyPass: loc.Proxy.Pass,
		}
	}
	// link=direct → без Tor/SOCKS; иначе Tor exit + split (RU direct, остальное через SOCKS).
	useTor := !strings.EqualFold(strings.TrimSpace(loc.Link), "direct")
	if useTor && loc.Proxy.Addr == "" {
		if proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
			cfg.SOCKS = olcrtcSocksConfig{
				ProxyAddr: proxyAddr,
				ProxyPort: proxyPort,
			}
			flags := readFeatureFlags()
			if flags["split"] || flags["zapret"] {
				cfg.SOCKS.DirectCIDRsFile = directCIDRsFileFromEnv()
				cfg.SOCKS.DirectDomainsFile = directDomainsFileFromEnv()
				cfg.SOCKS.BlockedTorDomainsFile = blockedTorDomainsFileFromEnv()
				cfg.SOCKS.ForceTorDomainsFile = forceTorDomainsFileFromEnv()
			}
		}
	}
'''
    new='''	// A configured global/client/instance proxy is the server-side egress.
	// It is separate from the local SOCKS listener in OlcBox. Split routing remains on by default.
	if proxyEnabled(loc.Proxy) {
		cfg.SOCKS = olcrtcSocksConfig{ProxyAddr: loc.Proxy.Addr, ProxyPort: loc.Proxy.Port, ProxyUser: loc.Proxy.User, ProxyPass: loc.Proxy.Pass}
		applyProxyRouting(&cfg, loc.Proxy.Routing)
	} else if !strings.EqualFold(strings.TrimSpace(loc.Link), "direct") {
		if proxyAddr, proxyPort := exitProxyFromEnv(); proxyAddr != "" {
			cfg.SOCKS = olcrtcSocksConfig{ProxyAddr: proxyAddr, ProxyPort: proxyPort}
			applyProxyRouting(&cfg, "split")
		}
	}
'''
    s=one(s,old,new,'safe server proxy config')
    s += '\n// '+MARKER+'\n'
    path.write_text(s)
    test=path.with_name('proxy_policy_patch_test.go')
    test.write_text('''package main

import "testing"

func proxyTest(enabled bool, addr string) Socks5Proxy { return Socks5Proxy{Enabled: boolPointer(enabled), Addr: addr, Port: 1080, Routing: "split"} }
func TestProxyPolicyPrecedenceAndPersistence(t *testing.T) {
	loc := Location{ClientID: "c", Proxy: proxyTest(true, "instance")}
	cfg := Config{Clients: []Client{{ClientID: "c", Proxy: proxyTest(true, "client")}}}
	got, source := effectiveProxyPolicyWithGlobal(proxyTest(true, "global"), cfg, loc)
	if source != "global" || got.Addr != "global" { t.Fatalf("global: source=%s addr=%s", source, got.Addr) }
	got, source = effectiveProxyPolicyWithGlobal(proxyTest(false, "saved-global"), cfg, loc)
	if source != "client" || got.Addr != "client" { t.Fatalf("client: source=%s addr=%s", source, got.Addr) }
	cfg.Clients[0].Proxy.Enabled = boolPointer(false)
	got, source = effectiveProxyPolicyWithGlobal(proxyTest(false, "saved-global"), cfg, loc)
	if source != "instance" || got.Addr != "instance" { t.Fatalf("instance: source=%s addr=%s", source, got.Addr) }
	loc.Proxy.Enabled = boolPointer(false)
	_, source = effectiveProxyPolicyWithGlobal(proxyTest(false, "saved-global"), cfg, loc)
	if source != "automatic" { t.Fatalf("automatic: source=%s", source) }
}
''')

if __name__=='__main__':
    patch_go(Path(sys.argv[1]))