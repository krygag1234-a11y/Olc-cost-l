// Package routing provides destination-based path selection (direct vs proxy).
package routing

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
)

// Matcher tests whether an IP should use a direct path (bypass outbound proxy).
type Matcher struct {
	mu   sync.RWMutex
	nets []*net.IPNet
}

// LoadFile reads CIDR lines (one per line; # comments allowed).
func LoadFile(path string) (*Matcher, error) {
	if path == "" {
		return &Matcher{}, nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open cidr file: %w", err)
	}
	defer f.Close()

	var nets []*net.IPNet
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if !strings.Contains(line, "/") {
			line += "/32"
		}
		_, n, err := net.ParseCIDR(line)
		if err != nil {
			ip := net.ParseIP(line)
			if ip == nil {
				continue
			}
			if ip4 := ip.To4(); ip4 != nil {
				n = &net.IPNet{IP: ip4, Mask: net.CIDRMask(32, 32)}
			} else {
				n = &net.IPNet{IP: ip, Mask: net.CIDRMask(128, 128)}
			}
		}
		nets = append(nets, n)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return &Matcher{nets: nets}, nil
}

// Contains reports whether ip is inside any loaded network.
func (m *Matcher) Contains(ip net.IP) bool {
	if m == nil || ip == nil {
		return false
	}
	ip = ip.To4()
	if ip == nil {
		return false
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, n := range m.nets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

// Len returns the number of loaded CIDR entries.
func (m *Matcher) Len() int {
	if m == nil {
		return 0
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.nets)
}
