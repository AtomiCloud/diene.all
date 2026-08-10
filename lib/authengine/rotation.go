package authengine

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// RefreshRecord is the stored state of one issued refresh token.
//
// The raw token never appears here: only its fingerprint does, so a leaked store
// dump cannot be replayed against the IdP. That is also why reuse detection works
// at all — the fingerprint is stable across the token's life, and the Consumed
// flag is what distinguishes a legitimate first use from a replay.
type RefreshRecord struct {
	// Subject is the session owner.
	Subject string `json:"subject"`
	// Fingerprint is the stable hash of the raw refresh token.
	Fingerprint string `json:"fingerprint"`
	// IssuedAt is when the IdP issued the token.
	IssuedAt time.Time `json:"issuedAt"`
	// ExpiresAt is when the token stops being accepted.
	ExpiresAt time.Time `json:"expiresAt"`
	// Consumed reports whether the token has already been rotated away.
	Consumed bool `json:"consumed"`
}

// RefreshStore persists issued refresh-token records for rotation and reuse
// detection.
type RefreshStore interface {
	// Read returns the record stored for fingerprint and whether it was present.
	Read(ctx context.Context, fingerprint string) (RefreshRecord, bool, error)
	// Write stores record for ttl, overwriting any record with the same
	// fingerprint.
	Write(ctx context.Context, record RefreshRecord, ttl time.Duration) error
}

// RotatorOptions configures a [Rotator].
type RotatorOptions struct {
	// Provider performs the IdP refresh exchange.
	Provider Provider
	// Store persists issued-token records.
	Store RefreshStore
	// Problems mints problem-typed failures.
	Problems *Problems
	// Clock is the injected time seam.
	Clock interfaces.System
	// Lifetime is the refresh-token validity. Zero uses
	// [RefreshTokenLifetime].
	Lifetime time.Duration
}

// Rotator implements the family refresh-token contract: 14 days, rotating on
// every use, with reuse treated as theft.
//
// Rotation without reuse detection is barely better than a long-lived token: an
// attacker who copies a refresh token races the legitimate client, and whoever
// refreshes second simply gets a new token. Recording each issued fingerprint and
// refusing a second rotation turns that race into a hard, attributable failure —
// which is the whole point of rotating in the first place.
type Rotator struct {
	provider Provider
	store    RefreshStore
	problems *Problems
	clock    interfaces.System
	lifetime time.Duration
}

// NewRotator creates a rotator, rejecting a configuration missing any of its
// seams.
func NewRotator(options RotatorOptions) (Rotator, error) {
	if options.Problems == nil {
		return Rotator{}, errUnconfigured("refresh rotator")
	}
	if options.Provider == nil {
		return Rotator{}, options.Problems.Raise(ProblemConfigInvalid,
			"an identity provider is required to rotate refresh tokens", nil)
	}
	if options.Store == nil {
		return Rotator{}, options.Problems.Raise(ProblemConfigInvalid,
			"a refresh store is required so reuse is detectable", nil)
	}
	if options.Clock == nil {
		return Rotator{}, options.Problems.Raise(ProblemConfigInvalid,
			"a clock seam is required so refresh expiry stays injectable", nil)
	}
	lifetime := options.Lifetime
	if lifetime == 0 {
		lifetime = RefreshTokenLifetime
	}
	return Rotator{
		provider: options.Provider,
		store:    options.Store,
		problems: options.Problems,
		clock:    options.Clock,
		lifetime: lifetime,
	}, nil
}

// Issue records a freshly issued session's refresh token so a later rotation can
// recognise it. A session that was never issued cannot be rotated, which is what
// makes an unknown token distinguishable from a replayed one.
func (r Rotator) Issue(ctx context.Context, session Session) error {
	now, err := r.now()
	if err != nil {
		return err
	}
	fingerprint, err := r.Fingerprint(session.RefreshToken)
	if err != nil {
		return err
	}
	expiry := session.RefreshExpiresAt
	if expiry.IsZero() {
		expiry = now.Add(r.lifetime)
	}
	record := RefreshRecord{
		Subject:     session.Subject,
		Fingerprint: fingerprint,
		IssuedAt:    now,
		ExpiresAt:   expiry,
	}
	if err := r.store.Write(ctx, record, expiry.Sub(now)); err != nil {
		return r.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the refresh record could not be stored", nil)
	}
	return nil
}

// Rotate exchanges refreshToken for a new session, marking the presented token
// consumed and recording the replacement.
//
// It refuses an unknown token, an already-consumed token (reuse), and an expired
// one — each with its own problem id, because "sign in again" and "your session
// may be compromised" are different messages to a user.
func (r Rotator) Rotate(ctx context.Context, refreshToken string) (Session, error) {
	now, err := r.now()
	if err != nil {
		return Session{}, err
	}
	fingerprint, err := r.Fingerprint(refreshToken)
	if err != nil {
		return Session{}, err
	}
	record, found, err := r.store.Read(ctx, fingerprint)
	if err != nil {
		return Session{}, r.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the refresh record could not be read", nil)
	}
	if !found {
		return Session{}, r.problems.Raise(ProblemRefreshTokenUnknown,
			"the presented refresh token was never issued here", nil)
	}
	if record.Consumed {
		return Session{}, r.problems.Raise(ProblemRefreshTokenReused,
			"the presented refresh token has already been rotated away",
			map[string]any{"subject": record.Subject})
	}
	if !now.Before(record.ExpiresAt) {
		return Session{}, r.problems.Raise(ProblemTokenExpired,
			"the presented refresh token has expired",
			map[string]any{"subject": record.Subject})
	}

	rotated, err := r.provider.Refresh(ctx, refreshToken)
	if err != nil {
		return Session{}, err
	}

	record.Consumed = true
	if err := r.store.Write(ctx, record, record.ExpiresAt.Sub(now)); err != nil {
		return Session{}, r.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the rotated refresh token could not be marked consumed", nil)
	}
	if rotated.Subject == "" {
		rotated.Subject = record.Subject
	}
	if err := r.Issue(ctx, rotated); err != nil {
		return Session{}, err
	}
	return rotated, nil
}

// Fingerprint returns the stable digest a refresh token is recorded under. It is
// exported so a consumer can evict a specific record — for instance on sign-out —
// without ever having to store the raw token itself.
//
// A blank token is rejected rather than hashed (M33: blank is unset), because
// hashing the empty string would file every credential-less request under one
// shared record.
func (r Rotator) Fingerprint(refreshToken string) (string, error) {
	if refreshToken == "" {
		return "", r.problems.Raise(ProblemRefreshTokenUnknown,
			"a blank refresh token is not a token", nil)
	}
	digest := sha256.Sum256([]byte(refreshToken))
	return hex.EncodeToString(digest[:]), nil
}

// now reads the injected clock as a problem-typed operation.
func (r Rotator) now() (time.Time, error) {
	now, err := r.clock.NowUTC()
	if err != nil {
		return time.Time{}, r.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the clock seam could not supply the current instant", nil)
	}
	return now, nil
}
