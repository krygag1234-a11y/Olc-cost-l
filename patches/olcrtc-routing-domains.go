// Package routing — domain rules for split tunnel (direct vs Tor).
package routing

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"sync"
)

// National / regional TLDs: ANY host ending here → direct on RU VPS (no manual list needed).
var builtinRUSuffixes = []string{
	".ru",
	".su",
	".рф",
	".xn--p1ai", // .рф punycode
	".moscow",
	".xn--80adxhks", // .москва
	".xn--80asehdb", // .дети
	".xn--80aswg",   // .онлайн
	".xn--c1avg",    // .сайт
	".xn--80aqecdr1a", // .католик
	".xn--80aqecdr1a.xn--p1ai",
	".tatar",
}

// DomainMatcher matches hostnames that must use a direct path (RU VPS exit IP).
type DomainMatcher struct {
	mu     sync.RWMutex
	exact  map[string]struct{}
	suffix []string // includes leading dot
}

// NewDomainMatcher returns matcher with built-in RU TLD rules plus optional file.
func NewDomainMatcher() *DomainMatcher {
	return &DomainMatcher{exact: make(map[string]struct{})}
}

// LoadDomainsFile merges rules from file into matcher (built-in TLD rules always apply via Match).
func LoadDomainsFile(path string) (*DomainMatcher, error) {
	m := NewDomainMatcher()
	if path == "" {
		return m, nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open domains file: %w", err)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(strings.Split(sc.Text(), "#")[0])
		if line == "" {
			continue
		}
		m.addRule(line)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return m, nil
}

func (m *DomainMatcher) addRule(line string) {
	if strings.HasPrefix(line, "exact:") {
		h := strings.ToLower(strings.TrimPrefix(line, "exact:"))
		m.exact[h] = struct{}{}
		return
	}
	if strings.HasPrefix(line, "suffix:") {
		line = strings.ToLower(strings.TrimPrefix(line, "suffix:"))
	} else {
		line = strings.ToLower(line)
	}
	if !strings.HasPrefix(line, ".") {
		if strings.Contains(line, ".") {
			line = "." + line
		} else {
			// geosite single label "ru" → .ru
			line = "." + line
		}
	}
	m.mu.Lock()
	m.suffix = append(m.suffix, line)
	m.mu.Unlock()
}

// MatchBuiltinRU reports whether host is a Russian national TLD (any *.ru site).
func MatchBuiltinRU(host string) bool {
	host = strings.ToLower(strings.TrimSpace(host))
	if host == "" {
		return false
	}
	if strings.HasSuffix(host, ".ru") || host == "ru" {
		return true
	}
	for _, suf := range builtinRUSuffixes {
		if suf == ".ru" {
			continue
		}
		if host == strings.TrimPrefix(suf, ".") || strings.HasSuffix(host, suf) {
			return true
		}
	}
	// IDN .рф in unicode form
	if strings.HasSuffix(host, ".рф") {
		return true
	}
	return false
}

// Match reports whether host should bypass outbound Tor proxy.
func (m *DomainMatcher) Match(host string) bool {
	if MatchBuiltinRU(host) {
		return true
	}
	if m == nil {
		return false
	}
	host = strings.ToLower(strings.TrimSpace(host))
	if host == "" {
		return false
	}
	if _, ok := m.exact[host]; ok {
		return true
	}
	// subdomain of exact: cache.example.com for exact:example.com
	m.mu.RLock()
	defer m.mu.RUnlock()
	for exact := range m.exact {
		if host == exact || strings.HasSuffix(host, "."+exact) {
			return true
		}
	}
	for _, suf := range m.suffix {
		if host == strings.TrimPrefix(suf, ".") {
			return true
		}
		if strings.HasSuffix(host, suf) {
			return true
		}
	}
	return false
}

// Len returns approximate rule count (file rules only).
func (m *DomainMatcher) Len() int {
	if m == nil {
		return len(builtinRUSuffixes)
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(builtinRUSuffixes) + len(m.exact) + len(m.suffix)
}
