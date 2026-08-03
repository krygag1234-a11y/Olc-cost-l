package main

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
