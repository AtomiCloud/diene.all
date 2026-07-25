package authengine

import (
	"context"
	"errors"
	"time"
)

// AccessToken is a minted access token bound to one resource.
//
// The expiry travels with the value because a cache that only stores the string
// cannot tell a live token from a dead one, and re-minting on every call defeats
// the point of caching at all.
type AccessToken struct {
	// Value is the raw bearer value.
	Value string `json:"value"`
	// Resource is the resource-tree name the token was minted for.
	Resource string `json:"resource"`
	// Scopes are the scopes the token was granted.
	Scopes []string `json:"scopes"`
	// IssuedAt is when the IdP minted the token.
	IssuedAt time.Time `json:"issuedAt"`
	// ExpiresAt is when the token stops being accepted.
	ExpiresAt time.Time `json:"expiresAt"`
}

// Expired reports whether the token is spent at now, treating anything within
// skew of expiry as already spent so a caller never receives a token that dies
// mid-request.
func (t AccessToken) Expired(now time.Time, skew time.Duration) bool {
	return !now.Add(skew).Before(t.ExpiresAt)
}

// TTL returns the remaining lifetime at now, clamped at zero.
func (t AccessToken) TTL(now time.Time) time.Duration {
	remaining := t.ExpiresAt.Sub(now)
	if remaining < 0 {
		return 0
	}
	return remaining
}

// Session is one authenticated user session's token pair.
type Session struct {
	// Subject is the session owner's `sub`.
	Subject string
	// Access is the current access token.
	Access AccessToken
	// RefreshToken is the current refresh token. It rotates on every use.
	RefreshToken string
	// RefreshExpiresAt is when the refresh token stops being accepted.
	RefreshExpiresAt time.Time
}

// ResourceTokenRequest asks the IdP for a token scoped to one resource.
type ResourceTokenRequest struct {
	// Subject is the session owner the token is minted for.
	Subject string
	// RefreshToken is the session's current refresh token.
	RefreshToken string
	// Resource is the resource-tree entry to mint for.
	Resource Resource
}

// ClientCredentialsRequest asks the IdP for a machine-to-machine token.
//
// There is no subject: a client-credentials token represents the CLIENT, which
// is exactly why the operator uses this flow rather than impersonating a user.
type ClientCredentialsRequest struct {
	// Resource is the resource-tree entry to mint for.
	Resource Resource
}

// OneTimeTokenRequest asks the IdP to mint a one-time login token, used when a
// deferred deep-link nonce is redeemed.
type OneTimeTokenRequest struct {
	// Subject is the identity the one-time token logs in.
	Subject string
	// Email is the address the IdP binds the one-time token to, when it requires
	// one.
	Email *string
}

// OneTimeToken is a short-lived single-use login token.
//
// Its lifetime is [OneTimeTokenLifetime] — 120 seconds — and it must never be
// confused with an access token: it is a redemption nonce, not a credential to
// cache.
type OneTimeToken struct {
	// Value is the raw one-time token.
	Value string
	// ExpiresAt is when redemption stops being possible.
	ExpiresAt time.Time
}

// Provider is the IdP seam every outbound identity call goes through.
//
// Logto is the only implementation in v1 (see the logto package) and no second
// IdP is planned, but the seam still earns its place: it is what lets consumer
// tests drive token minting, rotation, and claim write-back without a live
// tenant, and it keeps the IdP's HTTP shape out of the engine's decisions.
type Provider interface {
	// ResourceToken mints an access token for one resource of a user session.
	ResourceToken(ctx context.Context, request ResourceTokenRequest) (AccessToken, error)
	// Refresh rotates a refresh token, returning the new session pair. The
	// implementation must reject a refresh token it has already rotated.
	Refresh(ctx context.Context, refreshToken string) (Session, error)
	// ClientCredentials mints a machine-to-machine access token.
	ClientCredentials(ctx context.Context, request ClientCredentialsRequest) (AccessToken, error)
	// MintOneTimeToken mints a single-use login token.
	MintOneTimeToken(ctx context.Context, request OneTimeTokenRequest) (OneTimeToken, error)
	// SetClaim writes a custom-data claim back onto the IdP user, which is how
	// OnboardSync records registration.
	SetClaim(ctx context.Context, subject string, name string, value any) error
}

// Retriever resolves the access token for a registered resource.
//
// Both a user-session cache and a machine-to-machine cache satisfy it, so a
// consumer's outbound client only ever depends on "give me a token for backend
// X" and never on which flow produced it.
type Retriever interface {
	// Token returns a live access token for the named resource.
	Token(ctx context.Context, resource string) (AccessToken, error)
}

// errUnconfigured reports a constructor called without the problem factory every
// other failure is expressed through. It is a plain error by necessity: there is
// no factory available to raise a problem-typed one.
func errUnconfigured(component string) error {
	return errors.New("auth-engine " + component + " requires a problem factory")
}
