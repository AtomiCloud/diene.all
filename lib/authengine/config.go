package authengine

import "time"

// ConfigBlockKey is the root key a service composes this engine's configuration
// block under.
//
// The engine owns and exports its own block, next to the code that reads it. The
// CONFIG library is the sole merger and validator: it deep-merges the YAML layers
// and validates the service's composed root schema once. standard-config does not
// merge this block, and this library never reads a file or an environment
// variable itself.
const ConfigBlockKey = "auth"

// Config is the auth-engine's engine-owned configuration block.
//
// Note what is NOT here: the deferred nonce TTL and the IdP one-time-token
// expiry are fixed contract constants ([DeferredTokenLifetime],
// [OneTimeTokenLifetime]), not knobs, and neither are the access/refresh token
// lifetimes. Making them configurable would let one service quietly diverge from
// a contract the whole family depends on.
type Config struct {
	// IDP configures token validation against the identity provider.
	IDP IDPConfig `json:"idp"`
	// Minting configures outbound token acquisition.
	Minting MintingConfig `json:"minting"`
	// Resources declares the per-resource token tree.
	Resources []ResourceConfig `json:"resources"`
	// Policies declares the application's named claim policies.
	Policies PolicySet `json:"policies"`
}

// IDPConfig configures inbound token validation.
type IDPConfig struct {
	// Issuer is the OIDC issuer. It is BAKED build-time configuration: each
	// platform runs its own provider instance with its own issuer and user pool,
	// and the issuer is never sourced from a document fetched at runtime.
	Issuer string `json:"issuer"`
	// Audience is the resource audience access tokens must carry.
	Audience string `json:"audience"`
	// JWKSURI is the JSON Web Key Set endpoint.
	JWKSURI string `json:"jwksUri"`
	// Algorithms narrows the accepted signing algorithms. Empty uses
	// [DefaultAlgorithms].
	Algorithms []string `json:"algorithms"`
	// ClockSkewSeconds is the validation leeway. Zero uses [DefaultClockSkew].
	ClockSkewSeconds int `json:"clockSkewSeconds"`
	// Management configures the provider's management API, used for claim
	// write-back.
	Management ManagementConfig `json:"management"`
}

// Leeway returns the configured validation leeway, falling back to the family
// default.
func (c IDPConfig) Leeway() time.Duration {
	if c.ClockSkewSeconds <= 0 {
		return DefaultClockSkew
	}
	return time.Duration(c.ClockSkewSeconds) * time.Second
}

// ManagementConfig configures the provider's management API.
type ManagementConfig struct {
	// Endpoint is the management API base URL.
	Endpoint string `json:"endpoint"`
	// Resource is the management API resource indicator.
	Resource string `json:"resource"`
	// ClientID identifies the management application.
	ClientID string `json:"clientId"`
	// ClientSecret authenticates the management application. It is BLANK in
	// every committed YAML layer: the secret store injects it at runtime.
	ClientSecret string `json:"clientSecret"`
}

// MintingConfig configures outbound token acquisition.
type MintingConfig struct {
	// TokenEndpoint is the OAuth token endpoint.
	TokenEndpoint string `json:"tokenEndpoint"`
	// ClientID identifies this application to the provider.
	ClientID string `json:"clientId"`
	// ClientSecret authenticates this application. It is BLANK in every
	// committed YAML layer: the secret store injects it at runtime.
	ClientSecret string `json:"clientSecret"`
	// HandoffPath is the mount path of the deferred-login handoff endpoint. It is
	// configurable with a documented default, never hardcoded by a consumer.
	HandoffPath string `json:"handoffPath"`
	// CacheNamespace prefixes token cache keys. Blank uses
	// [DefaultTokenNamespace].
	CacheNamespace string `json:"cacheNamespace"`
	// RefreshSkewSeconds is how long before expiry a cached token is refreshed.
	// Zero uses [DefaultRefreshSkew].
	RefreshSkewSeconds int `json:"refreshSkewSeconds"`
	// Concurrency bounds the eager all-resources token batch. Zero uses
	// [DefaultTokenConcurrency].
	Concurrency int `json:"concurrency"`
}

// Skew returns the configured refresh skew, falling back to the family default.
func (c MintingConfig) Skew() time.Duration {
	if c.RefreshSkewSeconds <= 0 {
		return DefaultRefreshSkew
	}
	return time.Duration(c.RefreshSkewSeconds) * time.Second
}

// DefaultHandoffPath is the documented default mount of the deferred-login
// handoff endpoint. Consumers may mount it elsewhere; only the wire shapes are
// fixed by the contract.
const DefaultHandoffPath = "/app-handoff"

// Mount returns the configured handoff mount path, falling back to
// [DefaultHandoffPath].
func (c MintingConfig) Mount() string {
	if c.HandoffPath == "" {
		return DefaultHandoffPath
	}
	return c.HandoffPath
}

// ResourceConfig declares one entry of the per-resource token tree.
type ResourceConfig struct {
	// Name is the logical backend name.
	Name string `json:"name"`
	// Indicator is the OIDC resource indicator.
	Indicator string `json:"indicator"`
	// Scopes are the scopes requested for this resource.
	Scopes []string `json:"scopes"`
}

// Tree builds the resource tree this configuration declares, applying the same
// validation as [NewResourceTree] so a bad configuration fails at startup rather
// than on the first token request.
func (c Config) Tree(problems *Problems) (ResourceTree, error) {
	resources := make([]Resource, 0, len(c.Resources))
	for _, declared := range c.Resources {
		// ResourceConfig and Resource differ only in wire tags, so the conversion is
		// total: the config shape IS the domain shape here.
		resources = append(resources, Resource(declared))
	}
	return NewResourceTree(problems, resources...)
}

// ConfigBlockSchema returns the JSON Schema of the engine's configuration block.
//
// It is exported so a service composes its root schema by importing one block per
// engine rather than restating every engine's keys, and so the CONFIG library can
// validate the merged layer against it. The `$schema` marker lives on the
// service's composed root document, not here: this is a fragment.
func ConfigBlockSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"required":             []any{"idp"},
		"properties": map[string]any{
			"idp":       idpSchema(),
			"minting":   mintingSchema(),
			"resources": resourcesSchema(),
			"policies":  policiesSchema(),
		},
	}
}

// idpSchema describes the inbound-validation half of the block.
func idpSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"required":             []any{"issuer", "jwksUri"},
		"properties": map[string]any{
			"issuer":           map[string]any{"type": "string", "format": "uri", "minLength": 1},
			"audience":         map[string]any{"type": "string"},
			"jwksUri":          map[string]any{"type": "string", "format": "uri", "minLength": 1},
			"algorithms":       stringListSchema(),
			"clockSkewSeconds": map[string]any{"type": "integer", "minimum": 0},
			"management": map[string]any{
				"type":                 "object",
				"additionalProperties": false,
				"properties": map[string]any{
					"endpoint":     map[string]any{"type": "string"},
					"resource":     map[string]any{"type": "string"},
					"clientId":     map[string]any{"type": "string"},
					"clientSecret": map[string]any{"type": "string"},
				},
			},
		},
	}
}

// mintingSchema describes the outbound-minting half of the block.
func mintingSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"tokenEndpoint":      map[string]any{"type": "string"},
			"clientId":           map[string]any{"type": "string"},
			"clientSecret":       map[string]any{"type": "string"},
			"handoffPath":        map[string]any{"type": "string"},
			"cacheNamespace":     map[string]any{"type": "string"},
			"refreshSkewSeconds": map[string]any{"type": "integer", "minimum": 0},
			"concurrency":        map[string]any{"type": "integer", "minimum": 0},
		},
	}
}

// resourcesSchema describes the per-resource token tree.
func resourcesSchema() map[string]any {
	return map[string]any{
		"type": "array",
		"items": map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"required":             []any{"name", "indicator"},
			"properties": map[string]any{
				"name":      map[string]any{"type": "string", "minLength": 1},
				"indicator": map[string]any{"type": "string", "minLength": 1},
				"scopes":    stringListSchema(),
			},
		},
	}
}

// policiesSchema describes the named-policy registry.
func policiesSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"additionalProperties": map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"required":             []any{"type", "field", "target"},
			"properties": map[string]any{
				"type":   map[string]any{"enum": []any{string(PolicyAny), string(PolicyAll)}},
				"field":  map[string]any{"type": "string", "minLength": 1},
				"target": stringListSchema(),
			},
		},
	}
}

// stringListSchema describes a list of non-empty strings.
func stringListSchema() map[string]any {
	return map[string]any{
		"type":  "array",
		"items": map[string]any{"type": "string", "minLength": 1},
	}
}
