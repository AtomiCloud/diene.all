package authengine

import (
	"context"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// DefaultTokenNamespace is the key namespace a token cache uses when the
// consumer does not choose one.
const DefaultTokenNamespace = "auth-token"

// DefaultTokenConcurrency bounds the eager all-resources batch fetch.
const DefaultTokenConcurrency = 4

// TokenStore is the pluggable cache backing per-resource access tokens.
//
// It is a KV seam on purpose (S19): tokens are hot, short-lived, and shared
// across a consumer's replicas, so they belong in the KV tier and never in the
// relational store. A single-process consumer can bind the in-memory fake and
// lose nothing but sharing.
type TokenStore interface {
	// Get returns the token cached under key and whether it was present. A cache
	// miss is (zero, false, nil) — not an error.
	Get(ctx context.Context, key string) (AccessToken, bool, error)
	// Set caches token under key for ttl.
	Set(ctx context.Context, key string, token AccessToken, ttl time.Duration) error
	// Delete evicts key, succeeding when it was already absent.
	Delete(ctx context.Context, key string) error
}

// TokenSource mints a fresh access token for one resource. It is the flow half
// of token resolution: [SessionSource] mints on behalf of a user,
// [ClientCredentialsSource] mints on behalf of the client itself.
type TokenSource interface {
	// Mint returns a newly minted token for resource.
	Mint(ctx context.Context, resource Resource) (AccessToken, error)
}

// TokenCacheOptions configures a [TokenCache].
type TokenCacheOptions struct {
	// Tree declares the resources tokens may be resolved for.
	Tree ResourceTree
	// Store is the cache backing.
	Store TokenStore
	// Source mints tokens on a miss.
	Source TokenSource
	// Problems mints problem-typed failures.
	Problems *Problems
	// Clock is the injected time seam.
	Clock interfaces.System
	// Namespace prefixes cache keys. Blank uses [DefaultTokenNamespace].
	Namespace string
	// Skew is how long before expiry a cached token is treated as stale. Zero
	// uses [DefaultRefreshSkew].
	Skew time.Duration
	// Concurrency bounds [TokenCache.All]. Zero uses [DefaultTokenConcurrency].
	Concurrency int
}

// TokenCache resolves per-resource access tokens, caching them until they are
// nearly spent and collapsing concurrent misses into one mint.
//
// The single-flight behaviour is the load-bearing part. Without it, N concurrent
// requests arriving on a cold or just-expired cache each mint their own token:
// the IdP sees an N-fold spike exactly when a service is busiest, and — with
// rotating refresh tokens — the losers of that race hold tokens the winner has
// already invalidated. With it, N callers await one mint and all observe the same
// token.
type TokenCache struct {
	tree        ResourceTree
	store       TokenStore
	source      TokenSource
	problems    *Problems
	clock       interfaces.System
	namespace   string
	skew        time.Duration
	concurrency int
	flight      *tokenFlight
}

// NewTokenCache creates a token cache, rejecting a configuration missing any of
// its seams.
func NewTokenCache(options TokenCacheOptions) (*TokenCache, error) {
	if options.Problems == nil {
		return nil, errUnconfigured("token cache")
	}
	if options.Store == nil {
		return nil, options.Problems.Raise(ProblemConfigInvalid,
			"a token store is required so tokens survive beyond one call", nil)
	}
	if options.Source == nil {
		return nil, options.Problems.Raise(ProblemConfigInvalid,
			"a token source is required to mint on a cache miss", nil)
	}
	if options.Clock == nil {
		return nil, options.Problems.Raise(ProblemConfigInvalid,
			"a clock seam is required so token expiry stays injectable", nil)
	}
	namespace := options.Namespace
	if namespace == "" {
		namespace = DefaultTokenNamespace
	}
	skew := options.Skew
	if skew == 0 {
		skew = DefaultRefreshSkew
	}
	concurrency := options.Concurrency
	if concurrency <= 0 {
		concurrency = DefaultTokenConcurrency
	}
	return &TokenCache{
		tree:        options.Tree,
		store:       options.Store,
		source:      options.Source,
		problems:    options.Problems,
		clock:       options.Clock,
		namespace:   namespace,
		skew:        skew,
		concurrency: concurrency,
		flight:      newTokenFlight(),
	}, nil
}

// Token returns a live access token for the named resource, minting one only
// when the cache holds nothing usable.
func (c *TokenCache) Token(ctx context.Context, name string) (AccessToken, error) {
	resource, err := c.tree.Require(name)
	if err != nil {
		return AccessToken{}, err
	}
	key, err := c.Key(name)
	if err != nil {
		return AccessToken{}, err
	}
	now, err := c.now()
	if err != nil {
		return AccessToken{}, err
	}

	cached, found, err := c.store.Get(ctx, key)
	if err != nil {
		return AccessToken{}, c.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the token store could not be read", map[string]any{"resource": name})
	}
	if found && !cached.Expired(now, c.skew) {
		return cached, nil
	}
	return c.mint(ctx, key, resource)
}

// All eagerly resolves a token for every declared resource as one logical batch.
//
// Onboarding fetches all per-resource tokens up front rather than lazily on first
// call: a lazy fetch turns every consumer's first request to every backend into a
// token round trip, and it interleaves badly with a stale registration claim,
// where the 401/404 recovery path is already the answer.
func (c *TokenCache) All(ctx context.Context) (map[string]AccessToken, error) {
	names := c.tree.Names()
	tokens, err := coreutils.MapConcurrent(ctx, names, c.concurrency,
		func(ctx context.Context, name string) (AccessToken, error) {
			return c.Token(ctx, name)
		})
	if err != nil {
		return nil, err
	}
	resolved := make(map[string]AccessToken, len(tokens))
	for index, token := range tokens {
		resolved[names[index]] = token
	}
	return resolved, nil
}

// Invalidate evicts the cached token for the named resource, which is what a
// consumer does when a backend rejects a token it believed was live.
func (c *TokenCache) Invalidate(ctx context.Context, name string) error {
	key, err := c.Key(name)
	if err != nil {
		return err
	}
	if err := c.store.Delete(ctx, key); err != nil {
		return c.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the token store could not be written", map[string]any{"resource": name})
	}
	return nil
}

// Key returns the namespaced cache key for the named resource, so a consumer
// sharing one KV across concerns can reason about what this cache owns.
func (c *TokenCache) Key(name string) (string, error) {
	key, err := coreutils.NamespacedKey(c.namespace, name)
	if err != nil {
		return "", c.problems.RaiseFrom(ProblemConfigInvalid, err,
			"the resource name is not a usable cache key", map[string]any{"resource": name})
	}
	return key, nil
}

// mint collapses concurrent misses for one resource into a single provider call
// and caches the result for the token's own remaining lifetime.
func (c *TokenCache) mint(ctx context.Context, key string, resource Resource) (AccessToken, error) {
	return c.flight.do(key, func() (AccessToken, error) {
		token, err := c.source.Mint(ctx, resource)
		if err != nil {
			return AccessToken{}, err
		}
		token.Resource = resource.Name
		now, err := c.now()
		if err != nil {
			return AccessToken{}, err
		}
		if err := c.store.Set(ctx, key, token, token.TTL(now)); err != nil {
			return AccessToken{}, c.problems.RaiseFrom(ProblemProviderUnavailable, err,
				"the minted token could not be cached", map[string]any{"resource": resource.Name})
		}
		return token, nil
	})
}

// now reads the injected clock, translating a clock failure into a problem so no
// caller has to handle two error shapes.
func (c *TokenCache) now() (time.Time, error) {
	now, err := c.clock.NowUTC()
	if err != nil {
		return time.Time{}, c.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the clock seam could not supply the current instant", nil)
	}
	return now, nil
}
