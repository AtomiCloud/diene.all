package deferred

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// Record is the stored state of one minted handoff nonce.
//
// The raw nonce is never stored: only its digest is, so a store dump cannot be
// redeemed. Consumed is recorded rather than the row being deleted, which is what
// lets a replay be reported as a replay instead of as an unknown token.
type Record struct {
	// Digest is the hash the nonce is filed under.
	Digest string `json:"digest"`
	// Subject is the session owner the nonce logs in.
	Subject string `json:"subject"`
	// Email is the address the provider binds the one-time token to, when known.
	Email *string `json:"email,omitempty"`
	// IssuedAt is when the nonce was minted.
	IssuedAt time.Time `json:"issuedAt"`
	// ExpiresAt is when the nonce stops being redeemable.
	ExpiresAt time.Time `json:"expiresAt"`
	// Consumed reports whether the nonce has already been redeemed.
	Consumed bool `json:"consumed"`
}

// Store is the pluggable backing for minted handoff nonces.
//
// Consume must be ATOMIC: it has to be the operation that decides a redemption,
// not a read the caller follows with a write. Two devices redeeming the same
// carrier concurrently is a real scenario, and a read-then-write store would let
// both win.
type Store interface {
	// Put stores record for ttl.
	Put(ctx context.Context, record Record, ttl time.Duration) error
	// Consume atomically marks the record for digest consumed and returns it as
	// it was BEFORE the call, so the caller can tell a first redemption from a
	// replay. A digest the store does not hold returns (zero, false, nil).
	Consume(ctx context.Context, digest string) (Record, bool, error)
}

// Handoff is a minted deferred-login nonce as the web client receives it.
type Handoff struct {
	// Token is the raw nonce. It is returned exactly once, at mint time.
	Token string
	// ExpiresAt is when redemption stops being possible.
	ExpiresAt time.Time
}

// MinterOptions configures a [Minter].
type MinterOptions struct {
	// Store persists minted nonces.
	Store Store
	// Provider mints the one-time login token at redeem time.
	Provider authengine.Provider
	// Problems mints problem-typed failures.
	Problems *authengine.Problems
	// Clock is the injected time seam.
	Clock interfaces.System
	// Lifetime overrides the nonce TTL. It exists for tests that need a short
	// window; production leaves it zero and takes the contract constant.
	Lifetime time.Duration
}

// Minter mints and redeems deferred deep-link login nonces.
//
// The provider one-time token is minted at REDEEM time, not at mint time. That
// ordering is the point: the 120-second provider token would otherwise expire
// while the user is still in the app store, and a nonce that is merely a pointer
// to a session is safe to leave sitting in a store carrier for fifteen minutes.
type Minter struct {
	store    Store
	provider authengine.Provider
	problems *authengine.Problems
	clock    interfaces.System
	lifetime time.Duration
}

// NewMinter creates a minter, rejecting a configuration missing any of its seams.
func NewMinter(options MinterOptions) (Minter, error) {
	if options.Problems == nil {
		return Minter{}, errUnconfigured()
	}
	if options.Store == nil {
		return Minter{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a deferred-login store is required so a nonce can be consumed exactly once", nil)
	}
	if options.Provider == nil {
		return Minter{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"an identity provider is required to mint the one-time login token", nil)
	}
	if options.Clock == nil {
		return Minter{}, options.Problems.Raise(authengine.ProblemConfigInvalid,
			"a clock seam is required so nonce expiry stays injectable", nil)
	}
	lifetime := options.Lifetime
	if lifetime == 0 {
		lifetime = authengine.DeferredTokenLifetime
	}
	return Minter{
		store:    options.Store,
		provider: options.Provider,
		problems: options.Problems,
		clock:    options.Clock,
		lifetime: lifetime,
	}, nil
}

// Mint issues a one-time nonce bound to an authenticated session.
func (m Minter) Mint(ctx context.Context, session authengine.Session, email *string) (Handoff, error) {
	if session.Subject == "" {
		return Handoff{}, m.problems.Raise(authengine.ProblemTokenClaimMissing,
			"a handoff nonce must be bound to an authenticated subject",
			map[string]any{"claim": authengine.ClaimSubject})
	}
	now, err := m.now()
	if err != nil {
		return Handoff{}, err
	}
	nonce := Nonce()
	expiry := now.Add(m.lifetime)
	record := Record{
		Digest:    Digest(nonce),
		Subject:   session.Subject,
		Email:     email,
		IssuedAt:  now,
		ExpiresAt: expiry,
	}
	if err := m.store.Put(ctx, record, m.lifetime); err != nil {
		return Handoff{}, m.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the handoff nonce could not be stored", nil)
	}
	return Handoff{Token: nonce, ExpiresAt: expiry}, nil
}

// Exchange consumes a nonce exactly once and mints the provider one-time login
// token it stands for.
//
// Each refusal has its own problem id — unknown, already consumed, expired —
// because they mean different things to a client: an unknown nonce is a broken
// carrier, a consumed one is a replay or a double-tap, and an expired one just
// means the install took too long.
func (m Minter) Exchange(ctx context.Context, nonce string) (authengine.OneTimeToken, error) {
	if nonce == "" {
		return authengine.OneTimeToken{}, m.problems.Raise(authengine.ProblemDeferredTokenUnknown,
			"a blank handoff nonce is not a nonce", nil)
	}
	now, err := m.now()
	if err != nil {
		return authengine.OneTimeToken{}, err
	}
	record, found, err := m.store.Consume(ctx, Digest(nonce))
	if err != nil {
		return authengine.OneTimeToken{}, m.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the handoff nonce could not be consumed", nil)
	}
	if !found {
		return authengine.OneTimeToken{}, m.problems.Raise(authengine.ProblemDeferredTokenUnknown,
			"the handoff nonce is not known to this service", nil)
	}
	if record.Consumed {
		return authengine.OneTimeToken{}, m.problems.Raise(authengine.ProblemDeferredTokenConsumed,
			"the handoff nonce has already been redeemed",
			map[string]any{"subject": record.Subject})
	}
	if !now.Before(record.ExpiresAt) {
		return authengine.OneTimeToken{}, m.problems.Raise(authengine.ProblemDeferredTokenExpired,
			"the handoff nonce expired before it was redeemed",
			map[string]any{"subject": record.Subject})
	}
	return m.provider.MintOneTimeToken(ctx, authengine.OneTimeTokenRequest{
		Subject: record.Subject,
		Email:   record.Email,
	})
}

// Digest returns the hash a nonce is stored under, so a consumer implementing
// [Store] never has to invent its own key derivation — or worse, store the nonce.
func Digest(nonce string) string {
	sum := sha256.Sum256([]byte(nonce))
	return hex.EncodeToString(sum[:])
}

// errUnconfigured reports a constructor called without the problem factory every
// other failure is expressed through. It is a plain error by necessity: there is
// no factory available to raise a problem-typed one.
func errUnconfigured() error {
	return errors.New("auth-engine deferred minter requires a problem factory")
}

// Nonce generates a fresh handoff nonce from the cryptographic random source.
//
// It is exported so a consumer minting a carrier for a flow this package does not
// model still derives its nonce the same way, rather than reaching for a
// timestamp or a UUID. rand.Text is total by contract: it fills its result from
// the system source and panics rather than returning a weak value, so there is no
// failure mode to handle here.
func Nonce() string {
	return rand.Text()
}

// now reads the injected clock as a problem-typed operation.
func (m Minter) now() (time.Time, error) {
	now, err := m.clock.NowUTC()
	if err != nil {
		return time.Time{}, m.problems.RaiseFrom(authengine.ProblemProviderUnavailable, err,
			"the clock seam could not supply the current instant", nil)
	}
	return now, nil
}
