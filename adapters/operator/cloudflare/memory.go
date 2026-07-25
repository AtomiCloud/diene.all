package cloudflare

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"sync"
)

// Memory is the in-memory Port fake for the unit/int tiers and the e2e fake-CF
// profile. Fault injection is explicit: InvalidTokens fails ValidateToken,
// FailConfigPush reddens PushTunnelConfig, UncoveredZones fails the exact-host
// TLS preflight, and RaceCreates makes CreateAccessApplication 409 like CF's
// duplicate-create while still registering the application (the adopt path
// must then find it via LIST).
type Memory struct {
	mu             sync.Mutex
	InvalidTokens  map[string]bool
	Policies       map[string]string
	Tunnels        map[string]Tunnel
	Configs        map[string][]IngressRule
	ConfigPushes   map[string]int
	Applications   map[string]AccessApplication
	ApplicationIDs map[string]string
	DNS            map[string]string
	UncoveredZones map[string]bool
	FailConfigPush bool
	RaceCreates    bool
	Writes         []string
}

// NewMemory constructs an empty fake.
func NewMemory() *Memory {
	return &Memory{
		InvalidTokens: map[string]bool{}, Policies: map[string]string{},
		Tunnels: map[string]Tunnel{}, Configs: map[string][]IngressRule{},
		ConfigPushes:   map[string]int{},
		Applications:   map[string]AccessApplication{}, ApplicationIDs: map[string]string{},
		DNS: map[string]string{}, UncoveredZones: map[string]bool{},
	}
}

// ValidateToken accepts any non-empty credentials not marked invalid.
func (m *Memory) ValidateToken(_ context.Context, credentials Credentials) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if credentials.AccountID == "" || credentials.APIToken == "" || m.InvalidTokens[credentials.APIToken] {
		return ErrInvalidToken
	}
	return nil
}

// EnsureTunnel finds or creates the named tunnel (idempotent-once).
func (m *Memory) EnsureTunnel(_ context.Context, credentials Credentials, name, _ string) (Tunnel, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := credentials.AccountID + "/" + name
	if tunnel, ok := m.Tunnels[key]; ok {
		return tunnel, nil
	}
	tunnel := Tunnel{ID: "tunnel-" + name, Name: name, CNAME: "tunnel-" + name + ".cfargotunnel.com", Token: "token-" + name}
	m.Tunnels[key] = tunnel
	m.Writes = append(m.Writes, "tunnel:"+key)
	return tunnel, nil
}

// PushTunnelConfig stores the versioned remote config (hot-reload semantics:
// replicas read it live; no restart is modeled and none is needed).
func (m *Memory) PushTunnelConfig(_ context.Context, credentials Credentials, tunnelID string, rules []IngressRule) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.FailConfigPush {
		return fmt.Errorf("push tunnel config %s: injected failure", tunnelID)
	}
	key := credentials.AccountID + "/" + tunnelID
	m.Configs[key] = slices.Clone(rules)
	m.ConfigPushes[key]++
	m.Writes = append(m.Writes, "config:"+tunnelID)
	return nil
}

// CheckTLSCoverage proves exact-host coverage unless the zone is marked
// uncovered. The fake never assumes wildcard coverage for a deeper hostname —
// mirroring the fail-closed production preflight.
func (m *Memory) CheckTLSCoverage(_ context.Context, _ Credentials, zone, hostname string) (TLSCoverage, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.UncoveredZones[zone] {
		return TLSCoverage{Message: fmt.Sprintf("zone %s has no certificate product covering %s", zone, hostname)}, nil
	}
	if !strings.HasSuffix(hostname, "."+zone) && hostname != zone {
		return TLSCoverage{Message: fmt.Sprintf("hostname %s is outside zone %s", hostname, zone)}, nil
	}
	return TLSCoverage{Covered: true}, nil
}

// LookupPolicies resolves each name to its id; missing names are absent.
func (m *Memory) LookupPolicies(_ context.Context, _ Credentials, names []string) (map[string]string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	resolved := make(map[string]string, len(names))
	for _, name := range names {
		if id, ok := m.Policies[name]; ok {
			resolved[name] = id
		}
	}
	return resolved, nil
}

func applicationKey(credentials Credentials, hostname, path string) string {
	return credentials.AccountID + "/" + hostname + path
}

// FindAccessApplication LISTs for an application on hostname+path.
func (m *Memory) FindAccessApplication(_ context.Context, credentials Credentials, hostname, path string) (string, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	id, ok := m.ApplicationIDs[applicationKey(credentials, hostname, path)]
	return id, ok, nil
}

// CreateAccessApplication creates the application, or 409s when it already
// exists (or when RaceCreates injects the duplicate-create race by registering
// the application and still returning the 409, like a concurrent creator).
func (m *Memory) CreateAccessApplication(_ context.Context, credentials Credentials, desired AccessApplication) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := applicationKey(credentials, desired.Hostname, desired.Path)
	if _, exists := m.ApplicationIDs[key]; exists {
		return "", ErrApplicationAlreadyExists
	}
	id := fmt.Sprintf("app-%d", len(m.ApplicationIDs)+1)
	m.ApplicationIDs[key] = id
	m.Applications[key] = desired
	m.Writes = append(m.Writes, "app-create:"+key)
	if m.RaceCreates {
		return "", ErrApplicationAlreadyExists
	}
	return id, nil
}

// UpdateAccessApplication converges an existing application to desired.
func (m *Memory) UpdateAccessApplication(_ context.Context, credentials Credentials, id string, desired AccessApplication) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := applicationKey(credentials, desired.Hostname, desired.Path)
	if m.ApplicationIDs[key] != id {
		return fmt.Errorf("access application %s: not found", id)
	}
	m.Applications[key] = desired
	m.Writes = append(m.Writes, "app-update:"+key)
	return nil
}

// UpsertProxiedCNAME programs the proxied CNAME for hostname.
func (m *Memory) UpsertProxiedCNAME(_ context.Context, credentials Credentials, zone, hostname, target string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.DNS[credentials.AccountID+"/"+zone+"/"+hostname] = target
	m.Writes = append(m.Writes, "dns:"+hostname)
	return nil
}

// DeleteAccessApplication removes an application by id.
func (m *Memory) DeleteAccessApplication(_ context.Context, _ Credentials, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for key, existing := range m.ApplicationIDs {
		if existing == id {
			delete(m.ApplicationIDs, key)
			delete(m.Applications, key)
			m.Writes = append(m.Writes, "app-delete:"+key)
			return nil
		}
	}
	return nil
}

// DeleteDNSRecord removes the proxied CNAME for hostname.
func (m *Memory) DeleteDNSRecord(_ context.Context, credentials Credentials, zone, hostname string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.DNS, credentials.AccountID+"/"+zone+"/"+hostname)
	m.Writes = append(m.Writes, "dns-delete:"+hostname)
	return nil
}

// WriteCount reports how many provider writes have happened (used to assert
// "nothing programmed" refusals).
func (m *Memory) WriteCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.Writes)
}
