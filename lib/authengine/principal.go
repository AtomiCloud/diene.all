package authengine

import (
	"slices"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Principal is the domain identity mapped from a validated token's claim set.
//
// It is the only identity the rest of the engine trusts: every field here comes
// from a signature-verified token, never from a request body, header, or query
// field. Optional claims are pointers so "absent" stays distinguishable from
// "empty", which is exactly the distinction the onboarding gate branches on.
type Principal struct {
	// Subject is the IdP `sub` claim: the stable user id the ownership guard
	// compares a caller-supplied userId against.
	Subject string
	// Issuer is the `iss` claim the token was validated against.
	Issuer string
	// Audience is the `aud` claim list.
	Audience []string
	// Username is the IdP username, absent when the token omits it.
	Username *string
	// Email is the verified-or-not email address, absent when the token omits it.
	Email *string
	// EmailVerified reports whether the IdP has verified Email.
	EmailVerified bool
	// Roles are the coarse role claims the guard's role half reads.
	Roles []string
	// Scopes are the OAuth scopes granted to the token.
	Scopes []string
	// HomeLandscape is the landscape a caller's home traffic routes to, absent
	// for a caller that has not yet been through the pre-onboarding selector.
	HomeLandscape *string
	// ExpiresAt is the token expiry, zero when the token omits `exp`.
	ExpiresAt time.Time
	// Claims is the full validated claim set, so a consumer can read its own
	// custom claims without this library having to know about them.
	Claims Claims
}

// HasRole reports whether the principal carries role in its role claims.
func (p Principal) HasRole(role string) bool {
	return slices.Contains(p.Roles, role)
}

// HasScope reports whether the principal carries scope in its scope claims.
func (p Principal) HasScope(scope string) bool {
	return slices.Contains(p.Scopes, scope)
}

// Registered reports whether the principal carries the registration claim for
// backend, meaning OnboardSync has already completed against it.
//
// A claim that is absent and a claim that is present-and-false are both "not
// registered" here, but only the absent case is an onboarding trigger — read
// [Claims.Flag] directly when that distinction matters.
func (p Principal) Registered(backend string) bool {
	registered, _ := p.Claims.Flag(RegistrationClaim(backend))
	return registered
}

// RegistrationClaim returns the per-backend registration claim key for a backend
// target, following the family `<platform>_<service>` convention: the target is
// slugified and its separators become underscores, so the backend
// "Alcohol Zinc" and the target "alcohol-zinc" both resolve to `alcohol_zinc`.
//
// One client onboards to many backends, so this key is deliberately derived
// rather than configured: a per-backend key that drifts from the backend's own
// name is a silent onboarding loop.
func RegistrationClaim(backend string) string {
	return strings.ReplaceAll(coreutils.Slugify(backend), "-", "_")
}

// ClaimMapper maps a validated claim set onto a [Principal].
//
// The claim names are configurable because an IdP tenant may emit roles or the
// home landscape under a different key, but the mapping itself is total: a
// wrong-typed or absent claim yields an absent field, never an error, because a
// token that validated cryptographically must not be rejected for cosmetic claim
// shape.
type ClaimMapper struct {
	// RolesClaim is the claim carrying coarse role names.
	RolesClaim string
	// ScopeClaim is the claim carrying space-delimited OAuth scopes.
	ScopeClaim string
	// HomeLandscapeClaim is the claim carrying the home landscape name.
	HomeLandscapeClaim string
}

// NewClaimMapper returns the mapper for the family's default claim names.
func NewClaimMapper() ClaimMapper {
	return ClaimMapper{
		RolesClaim:         ClaimRoles,
		ScopeClaim:         ClaimScope,
		HomeLandscapeClaim: ClaimHomeLandscape,
	}
}

// Map folds claims into a Principal. Claim names left blank on the mapper fall
// back to the family defaults, so a partially configured mapper still behaves.
func (m ClaimMapper) Map(claims Claims) Principal {
	roles, _ := claims.List(orDefault(m.RolesClaim, ClaimRoles))
	scopes, _ := claims.Space(orDefault(m.ScopeClaim, ClaimScope))
	audience, _ := claims.List(ClaimAudience)
	subject, _ := claims.Text(ClaimSubject)
	issuer, _ := claims.Text(ClaimIssuer)
	verified, _ := claims.Flag(ClaimEmailVerified)
	expiry, _ := claims.Instant(ClaimExpiry)
	return Principal{
		Subject:       subject,
		Issuer:        issuer,
		Audience:      audience,
		Username:      optional(claims, ClaimUsername),
		Email:         optional(claims, ClaimEmail),
		EmailVerified: verified,
		Roles:         roles,
		Scopes:        scopes,
		HomeLandscape: optional(claims, orDefault(m.HomeLandscapeClaim, ClaimHomeLandscape)),
		ExpiresAt:     expiry,
		Claims:        claims.Clone(),
	}
}

// optional reads a string claim into a pointer so an absent claim stays absent
// rather than collapsing into the empty string.
func optional(claims Claims, name string) *string {
	value, found := claims.Text(name)
	if !found {
		return nil
	}
	return &value
}

// orDefault substitutes fallback for a blank configured claim name (M33: a blank
// value is unset, not a claim named "").
func orDefault(value string, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
