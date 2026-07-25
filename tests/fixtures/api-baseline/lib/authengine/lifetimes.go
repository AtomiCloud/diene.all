package authengine

import "time"

// Family-wide token lifetimes (ARCHITECTURE §5). These are fixed contract
// constants shared by every language family, not configuration knobs: a
// consumer that needs a different window is diverging from the contract rather
// than tuning it.
const (
	// AccessTokenLifetime is the validity of an issued access token. Consumers
	// re-mint on open, so a fresh session always starts from a fresh token.
	AccessTokenLifetime = 10 * time.Minute
	// RefreshTokenLifetime is the validity of an issued refresh token. Refresh
	// tokens rotate on every use and reuse of a consumed one is treated as
	// theft (see [Rotator]).
	RefreshTokenLifetime = 14 * 24 * time.Hour
	// DeferredTokenLifetime is the TTL of the deferred deep-link login nonce.
	// It is a contract constant rather than a schema knob.
	DeferredTokenLifetime = 15 * time.Minute
	// OneTimeTokenLifetime is the expiresIn of the IdP one-time login token
	// minted when a deferred nonce is redeemed. It is deliberately far shorter
	// than [AccessTokenLifetime] and must never be conflated with it.
	OneTimeTokenLifetime = 120 * time.Second
)

// Validation and refresh tolerances. Unlike the lifetimes above these are
// defaults: a consumer may override them through the engine config block.
const (
	// DefaultRefreshSkew is how long before expiry a cached access token is
	// treated as stale, so a token is never handed out moments before it dies.
	DefaultRefreshSkew = 30 * time.Second
	// DefaultClockSkew is the validation leeway absorbing clock drift between
	// the issuer and the verifier.
	DefaultClockSkew = 60 * time.Second
)
