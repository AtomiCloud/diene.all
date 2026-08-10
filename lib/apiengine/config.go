package apiengine

import (
	"slices"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// ConfigBlockKey is the root key this engine owns in a consumer's merged
// configuration (C0 §3: every engine owns its own block).
//
// This library neither merges nor validates the wider document — the config lib
// is the sole merger and validator. It only declares the shape of its own block
// and validates the block once a consumer hands it over.
const ConfigBlockKey = "api"

// DefaultTimeout is the per-request timeout applied when a backend declares
// none.
const DefaultTimeout = wire.Duration(30 * time.Second)

// Config is the api-engine's owned configuration block.
//
// It carries exactly what the engine itself needs: which backends exist and
// where they live, how to ask the auth-engine for each one's credentials, and
// the single retry knob the resilience profile permits.
type Config struct {
	// Backends maps the logical backend name a caller resolves clients by to
	// that backend's settings. The name is also the auth-engine resource name
	// unless the backend overrides it.
	Backends map[string]BackendConfig `json:"backends"`
	// Retry is the client resilience profile.
	Retry RetryConfig `json:"retry"`
}

// BackendConfig is one registered backend.
//
// Each registered backend is ONE hostname. Client-side routing between regions
// is deliberately absent (ARCHITECTURE §4): the DNS gray zone owns routing, so a
// region is just another registered backend rather than a list of hosts this
// client chooses between.
type BackendConfig struct {
	// BaseURL is the backend's single origin, e.g. `https://api.example.com`.
	BaseURL string `json:"baseUrl"`
	// Resource overrides the auth-engine resource name tokens are resolved
	// under. Blank means "use the backend name", which is the normal case.
	Resource string `json:"resource"`
	// Indicator is the OIDC resource indicator the IdP mints this backend's
	// tokens for. Blank means the backend needs no credentials.
	Indicator string `json:"indicator"`
	// Scopes are the scopes requested for this backend's tokens.
	Scopes []string `json:"scopes"`
	// Timeout is the per-request timeout as an ISO 8601 duration (C0 §1).
	// Zero means [DefaultTimeout].
	Timeout wire.Duration `json:"timeout"`
}

// RetryConfig is the client resilience profile: retry once on a network error,
// and nothing else.
//
// This is NOT load balancing and NOT a backoff ladder. A transport failure is
// retried exactly once — enough to ride out a connection reset or a pool
// closing under it — and then surfaces as a problem-typed error. Anything more
// turns a struggling backend into a stampede.
type RetryConfig struct {
	// Network enables the single transport retry. Default true.
	Network bool `json:"network"`
	// Delay is how long to wait before the one retry, as an ISO 8601 duration
	// (C0 §1). Zero retries immediately.
	Delay wire.Duration `json:"delay"`
}

// DefaultConfig returns the engine's defaults with no backends registered.
func DefaultConfig() Config {
	return Config{
		Backends: map[string]BackendConfig{},
		Retry:    RetryConfig{Network: true},
	}
}

// RequestTimeout returns the backend's per-request timeout, substituting
// [DefaultTimeout] when the backend declares none.
func (b BackendConfig) RequestTimeout() time.Duration {
	if b.Timeout == 0 {
		return DefaultTimeout.Std()
	}
	return b.Timeout.Std()
}

// Names returns the registered backend names in stable (sorted) order.
//
// Map iteration order is random in Go, so anything that enumerates backends —
// a client tree, a resource tree, a log line — sorts here rather than each
// growing its own ordering.
func (c Config) Names() []string {
	names := make([]string, 0, len(c.Backends))
	for name := range c.Backends {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// Resource returns the auth-engine resource name for the named backend,
// defaulting to the backend name itself.
func (c Config) Resource(name string) string {
	backend, found := c.Backends[name]
	if !found || strings.TrimSpace(backend.Resource) == "" {
		return name
	}
	return backend.Resource
}

// Validate rejects a configuration the engine refuses to start from.
//
// It fails on a blank backend name (M33: a blank value is unset, not a backend
// called ""), a blank or non-absolute base URL, and a negative timeout or retry
// delay. Validating once here means no client has to re-check its own origin on
// every call.
func (c Config) Validate(problems *Problems) error {
	if problems == nil {
		return errUnconfigured("configuration validation")
	}
	for _, name := range c.Names() {
		backend := c.Backends[name]
		if strings.TrimSpace(name) == "" {
			return problems.Raise(ProblemConfigInvalid,
				"a backend is registered under a blank name", nil)
		}
		base := strings.TrimSpace(backend.BaseURL)
		if base == "" {
			return problems.Raise(ProblemConfigInvalid,
				"a backend is registered without a base URL",
				map[string]any{"backend": name})
		}
		if !strings.HasPrefix(base, "http://") && !strings.HasPrefix(base, "https://") {
			return problems.Raise(ProblemConfigInvalid,
				"a backend base URL is not an absolute http(s) origin",
				map[string]any{"backend": name, "baseUrl": backend.BaseURL})
		}
		if backend.Timeout < 0 {
			return problems.Raise(ProblemConfigInvalid,
				"a backend declares a negative timeout",
				map[string]any{"backend": name, "timeout": backend.Timeout.String()})
		}
	}
	if c.Retry.Delay < 0 {
		return problems.Raise(ProblemConfigInvalid,
			"the retry delay is negative",
			map[string]any{"delay": c.Retry.Delay.String()})
	}
	return nil
}

// Tree converts the configured backends into an auth-engine resource tree, so
// the token cache, an onboarding round, and this client tree all agree on which
// backends exist from ONE declaration.
//
// Backends with no resource indicator are omitted: they need no credentials, so
// declaring them would ask the IdP to mint tokens nobody attaches.
func (c Config) Tree(authProblems *authengine.Problems) (authengine.ResourceTree, error) {
	resources := make([]authengine.Resource, 0, len(c.Backends))
	for _, name := range c.Names() {
		backend := c.Backends[name]
		if strings.TrimSpace(backend.Indicator) == "" {
			continue
		}
		resources = append(resources, authengine.Resource{
			Name:      c.Resource(name),
			Indicator: backend.Indicator,
			Scopes:    slices.Clone(backend.Scopes),
		})
	}
	return authengine.NewResourceTree(authProblems, resources...)
}

// ConfigBlockSchema returns the JSON Schema for this engine's owned block.
//
// A consumer composes this into its root schema alongside the other engines'
// blocks and its own keys; the config lib validates the merged document. This
// library publishes the shape and never validates the document itself.
func ConfigBlockSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"required":             []any{"backends"},
		"properties": map[string]any{
			"backends": map[string]any{
				"type":        "object",
				"description": "Registered backends keyed by logical backend name.",
				"additionalProperties": map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"required":             []any{"baseUrl"},
					"properties": map[string]any{
						"baseUrl": map[string]any{
							"type":        "string",
							"pattern":     "^https?://",
							"description": "The backend's single origin. One backend is one hostname.",
						},
						"resource": map[string]any{
							"type":        "string",
							"description": "Auth-engine resource name; defaults to the backend name.",
						},
						"indicator": map[string]any{
							"type":        "string",
							"description": "OIDC resource indicator. Blank means the backend needs no credentials.",
						},
						"scopes": stringListSchema(),
						"timeout": durationSchema(
							"Per-request timeout as an ISO 8601 duration (C0 §1), e.g. PT30S.",
						),
					},
				},
			},
			"retry": map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"description":          "Client resilience profile: retry once on a network error only.",
				"properties": map[string]any{
					"network": map[string]any{
						"type":        "boolean",
						"description": "Enable the single transport retry.",
					},
					"delay": durationSchema(
						"Delay before the one retry as an ISO 8601 duration (C0 §1), e.g. PT0.2S.",
					),
				},
			},
		},
	}
}

// durationSchema declares an ISO 8601 duration string (C0 §1).
func durationSchema(description string) map[string]any {
	return map[string]any{
		"type":        "string",
		"description": description,
	}
}

// stringListSchema declares an array of strings.
func stringListSchema() map[string]any {
	return map[string]any{
		"type":  "array",
		"items": map[string]any{"type": "string"},
	}
}
