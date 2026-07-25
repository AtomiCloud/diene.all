// Package cloudflare defines the provider boundary Boron reconciles against —
// token validation, tunnel + remote (API-pushed, hot-reload) configuration,
// exact-host DNS/edge-TLS coverage preflight, Access Application
// LIST-then-adopt-or-create, and Access policy LOOKUP by name (this operator
// never authors a policy) — plus an in-memory fake for tests and the e2e
// fake-CF profile.
package cloudflare

import (
	"context"
	"errors"
)

// ErrInvalidToken reports a credentials set Cloudflare rejects.
var ErrInvalidToken = errors.New("cloudflare token is invalid")

// ErrApplicationAlreadyExists mirrors CF's duplicate-create 409
// (access.api.error.application_already_exists). Reconcile handles it by
// falling back to the same LIST-then-adopt path, never as a hard error.
var ErrApplicationAlreadyExists = errors.New("access.api.error.application_already_exists")

// Credentials binds one Account CR's identity.
type Credentials struct {
	AccountID string
	APIToken  string
}

// Tunnel is a Cloudflare Tunnel projection.
type Tunnel struct {
	ID    string
	Name  string
	CNAME string
	Token string
}

// IngressRule is one hostname+path→backend rule in the tunnel's remote config.
type IngressRule struct {
	Hostname string
	Path     string
	Backend  string
}

// AccessApplication is the desired CF Access Application for one Exposure.
type AccessApplication struct {
	Name      string
	Hostname  string
	Path      string
	PolicyIDs []string
}

// TLSCoverage reports the exact-host DNS/edge-TLS preflight verdict.
type TLSCoverage struct {
	Covered bool
	Message string
}

// Port is the provider boundary the controllers depend on.
type Port interface {
	// ValidateToken checks the credentials once per Account.
	ValidateToken(ctx context.Context, credentials Credentials) error
	// EnsureTunnel finds or creates the named tunnel for the zone (idempotent-once).
	EnsureTunnel(ctx context.Context, credentials Credentials, name, zone string) (Tunnel, error)
	// PushTunnelConfig PUTs the versioned remote ingress configuration; running
	// cloudflared replicas long-poll and hot-reload it (no restart).
	PushTunnelConfig(ctx context.Context, credentials Credentials, tunnelID string, rules []IngressRule) error
	// CheckTLSCoverage preflights exact multi-label DNS/edge-TLS coverage for
	// hostname under zone. Universal SSL / one-label wildcards are never assumed.
	CheckTLSCoverage(ctx context.Context, credentials Credentials, zone, hostname string) (TLSCoverage, error)
	// LookupPolicies resolves each policy NAME to its CF Access policy id. A
	// missing name is reported by absence from the map, never an error: the
	// caller decides PolicyMissing.
	LookupPolicies(ctx context.Context, credentials Credentials, names []string) (map[string]string, error)
	// FindAccessApplication LISTs for an existing application on hostname+path.
	FindAccessApplication(ctx context.Context, credentials Credentials, hostname, path string) (id string, found bool, err error)
	// CreateAccessApplication creates the application. A duplicate-create race
	// returns ErrApplicationAlreadyExists for the LIST-then-adopt fallback.
	CreateAccessApplication(ctx context.Context, credentials Credentials, desired AccessApplication) (id string, err error)
	// UpdateAccessApplication converges an existing (found or adopted)
	// application to the desired policy set, in order.
	UpdateAccessApplication(ctx context.Context, credentials Credentials, id string, desired AccessApplication) error
	// UpsertProxiedCNAME programs the one proxied CNAME for the complete dotted
	// hostname to <tunnelID>.cfargotunnel.com.
	UpsertProxiedCNAME(ctx context.Context, credentials Credentials, zone, hostname, target string) error
	// DeleteAccessApplication removes an application on Exposure finalization.
	DeleteAccessApplication(ctx context.Context, credentials Credentials, id string) error
	// DeleteDNSRecord removes the proxied CNAME on Exposure finalization.
	DeleteDNSRecord(ctx context.Context, credentials Credentials, zone, hostname string) error
}
