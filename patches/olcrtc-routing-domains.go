// Package routing — domain rules for split tunnel (direct vs Tor).
package routing

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"sync"
)

// DomainMatcher matches hostnames that must use a direct path (RU VPS exit IP).
type DomainMatcher struct {
	mu      sync.RWMutex
	exact   map[string]struct{}
	suffix  []string // includes leading dot, e.g. ".ru"
}

// LoadDomainsFile reads rules: ".ru", ".рф", "okko.tv", "exact:foo.bar".
func LoadDomainsFile(path string) (*DomainMatcher, error) {
	if path == "" {
		return &DomainMatcher{}, nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open domains file: %w", err)
	}
	defer f.Close()

	m := &DomainMatcher{exact: make(map[string]struct{})}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(strings.Split(sc.Text(), "#")[0])
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "exact:") {
			h := strings.ToLower(strings.TrimPrefix(line, "exact:"))
			m.exact[h] = struct{}{}
			continue
		}
		line = strings.ToLower(line)
		if !strings.HasPrefix(line, ".") {
			line = "." + line
		}
		m.suffix = append(m.suffix, line)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return m, nil
}

// Match reports whether host should bypass outbound Tor proxy.
func (m *DomainMatcher) Match(host string) bool {
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
	m.mu.RLock()
	defer m.mu.RUnlock()
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

// Len returns rule count (approx).
func (m *DomainMatcher) Len() int {
	if m == nil {
		return 0
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.exact) + len(m.suffix)
}
