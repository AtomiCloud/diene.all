package authengine

import (
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// ProblemVersion is the contract version segment of every auth-engine problem
// type URI (C0 §2/D8). Bumping it mints new problem types rather than mutating
// the existing ones.
const ProblemVersion = "v1"

// Auth-engine problem ids. Every id is stable, catalogued, and resolves its RFC
// 9457 `type` URI through the single-source builder in the errors-problems
// sibling, so an auth failure is classifiable by a frontend without any
// auth-specific knowledge.
const (
	// ProblemTokenMalformed reports a bearer value that is not a parseable JWT.
	ProblemTokenMalformed = "token-malformed"
	// ProblemTokenExpired reports a token whose lifetime has elapsed.
	ProblemTokenExpired = "token-expired"
	// ProblemTokenSignatureInvalid reports a token whose signature does not
	// verify against the resolved JWKS key.
	ProblemTokenSignatureInvalid = "token-signature-invalid"
	// ProblemTokenIssuerMismatch reports a token minted by an untrusted issuer.
	ProblemTokenIssuerMismatch = "token-issuer-mismatch"
	// ProblemTokenAudienceMismatch reports a token minted for another audience.
	ProblemTokenAudienceMismatch = "token-audience-mismatch"
	// ProblemTokenClaimMissing reports a token that omits a claim the caller
	// requires, e.g. an onboarding token without a verified email.
	ProblemTokenClaimMissing = "token-claim-missing"
	// ProblemTokenSubjectMismatch reports two tokens that do not share one
	// subject — you may only ever onboard yourself.
	ProblemTokenSubjectMismatch = "token-subject-mismatch"
	// ProblemSigningKeyUnknown reports a `kid` the JWKS does not publish.
	ProblemSigningKeyUnknown = "signing-key-unknown"
	// ProblemResourceUnregistered reports a resource absent from the resource tree.
	ProblemResourceUnregistered = "resource-unregistered"
	// ProblemOwnershipDenied reports a failed ownership guard: the caller is
	// authenticated but neither owns the target nor holds a listed role.
	ProblemOwnershipDenied = "ownership-denied"
	// ProblemPolicyUnknown reports a named policy that the policy set omits.
	ProblemPolicyUnknown = "policy-unknown"
	// ProblemRegistrationMissing reports a caller whose per-backend registration
	// claim is absent, i.e. one that has not completed OnboardSync.
	ProblemRegistrationMissing = "registration-missing"
	// ProblemDeferredTokenUnknown reports a deferred-login nonce the store does
	// not hold.
	ProblemDeferredTokenUnknown = "deferred-token-unknown"
	// ProblemDeferredTokenExpired reports a deferred-login nonce past its TTL.
	ProblemDeferredTokenExpired = "deferred-token-expired"
	// ProblemDeferredTokenConsumed reports a replayed deferred-login nonce.
	ProblemDeferredTokenConsumed = "deferred-token-consumed"
	// ProblemRefreshTokenReused reports reuse of an already-rotated refresh
	// token, which the contract treats as theft rather than as a retry.
	ProblemRefreshTokenReused = "refresh-token-reused"
	// ProblemRefreshTokenUnknown reports a refresh token with no issued record.
	ProblemRefreshTokenUnknown = "refresh-token-unknown"
	// ProblemOnboardingStalled reports an onboarding round that created the
	// backend row but never observed the registration claim appear.
	ProblemOnboardingStalled = "onboarding-stalled"
	// ProblemHomeLandscapeUnresolved reports a pre-onboarding selector round
	// that found no healthy landscape to call home.
	ProblemHomeLandscapeUnresolved = "home-landscape-unresolved"
	// ProblemProviderUnavailable reports an IdP round trip that did not complete.
	ProblemProviderUnavailable = "provider-unavailable"
	// ProblemConfigInvalid reports an engine configuration the library refuses to
	// start from, e.g. a blank issuer or a duplicate resource name.
	ProblemConfigInvalid = "config-invalid"
)

// ProblemTypes returns the auth-engine's problem-type declarations in stable
// order. Consumers register them on their own registry and export them into
// their service catalog so the shipped problems appear in the published error
// portal alongside the service's own.
func ProblemTypes() []problem.Type {
	return []problem.Type{
		authProblem(ProblemTokenMalformed, "Token malformed", 401, false),
		authProblem(ProblemTokenExpired, "Token expired", 401, true),
		authProblem(ProblemTokenSignatureInvalid, "Token signature invalid", 401, false),
		authProblem(ProblemTokenIssuerMismatch, "Token issuer not trusted", 401, false),
		authProblem(ProblemTokenAudienceMismatch, "Token audience mismatch", 401, false),
		authProblem(ProblemTokenClaimMissing, "Token claim missing", 401, false),
		authProblem(ProblemTokenSubjectMismatch, "Token subject mismatch", 401, false),
		authProblem(ProblemSigningKeyUnknown, "Signing key unknown", 401, true),
		authProblem(ProblemResourceUnregistered, "Resource not registered", 400, false),
		authProblem(ProblemOwnershipDenied, "Ownership denied", 403, false),
		authProblem(ProblemPolicyUnknown, "Policy unknown", 500, false),
		authProblem(ProblemRegistrationMissing, "Registration missing", 403, true),
		authProblem(ProblemDeferredTokenUnknown, "Deferred token unknown", 401, false),
		authProblem(ProblemDeferredTokenExpired, "Deferred token expired", 401, true),
		authProblem(ProblemDeferredTokenConsumed, "Deferred token already consumed", 401, false),
		authProblem(ProblemRefreshTokenReused, "Refresh token reused", 401, false),
		authProblem(ProblemRefreshTokenUnknown, "Refresh token unknown", 401, false),
		authProblem(ProblemOnboardingStalled, "Onboarding stalled", 500, true),
		authProblem(ProblemHomeLandscapeUnresolved, "Home landscape unresolved", 503, true),
		authProblem(ProblemProviderUnavailable, "Identity provider unavailable", 502, true),
		authProblem(ProblemConfigInvalid, "Auth configuration invalid", 500, false),
	}
}

// authProblem declares one auth-engine problem type at the shared contract
// version, keeping the twenty-odd declarations above free of repetition.
func authProblem(id string, title string, status int, recoverable bool) problem.Type {
	return problem.Type{
		ID:          id,
		Title:       title,
		Version:     ProblemVersion,
		Status:      status,
		Recoverable: recoverable,
	}
}

// Problems mints the engine's problem-typed errors from a service's error
// portal.
//
// It is the single place auth failures become RFC 9457 envelopes: no other part
// of this library formats a type URI or picks a status code, which is what keeps
// the same failure identical whether it surfaces from the validator, the guard,
// the token cache, or the onboarding machine.
type Problems struct {
	registry *problem.Registry
}

// NewProblems creates the engine's problem factory bound to portal, optionally
// registering a consumer's own problem types alongside the engine's.
//
// The portal carries the service's own LPSM identity, so a validation failure
// raised inside a consumer is attributed to that consumer's error portal rather
// than to this library. Extra types share one registry with the engine's so a
// consumer exports ONE catalog; a type whose id collides with an engine problem is
// rejected rather than silently shadowing it.
func NewProblems(portal problem.ErrorPortal, extra ...problem.Type) (*Problems, error) {
	registry, err := problem.NewRegistry(portal, append(ProblemTypes(), extra...)...)
	if err != nil {
		return nil, err
	}
	return &Problems{registry: registry}, nil
}

// Registry returns the enumerable registry of the engine's problem types, for a
// consumer composing its own catalog.
func (p *Problems) Registry() *problem.Registry {
	return p.registry
}

// Catalog returns a catalog pre-populated with every type on this registry, ready
// to render Problem CR content (C0 §14).
//
// It deliberately does NOT add the portable generic set: which generics a service
// publishes is the service's decision, and a consumer that wants them calls
// AddGenerics on the returned catalog itself.
func (p *Problems) Catalog() (*problem.Catalog, error) {
	catalog := problem.NewCatalog(p.registry.Portal())
	for _, declared := range p.registry.Entries() {
		if err := catalog.AddType(declared); err != nil {
			return nil, err
		}
	}
	return catalog, nil
}

// Raise builds the problem-typed error registered for id, carrying detail and
// the typed data payload.
//
// It is total: an unregistered id yields an uncatalogued 500 problem rather than
// a second error to handle, because a failure to describe a failure must never
// replace it.
func (p *Problems) Raise(id string, detail string, data map[string]any) error {
	return problem.NewError(p.envelope(id, detail, data))
}

// RaiseFrom builds the problem-typed error registered for id wrapping cause, so
// errors.Is and errors.As still traverse into the underlying failure.
func (p *Problems) RaiseFrom(id string, cause error, detail string, data map[string]any) error {
	return problem.WrapError(p.envelope(id, detail, data), cause)
}

// envelope resolves id into an RFC 9457 envelope through the registry and the
// single-source type-URI builder, degrading to the uncatalogued fallback rather
// than failing.
func (p *Problems) envelope(id string, detail string, data map[string]any) problem.Problem {
	if data == nil {
		data = map[string]any{}
	}
	declared, found := p.registry.Lookup(id)
	if !found {
		return p.uncatalogued(detail, data)
	}
	uri, err := p.registry.TypeURIFor(declared)
	if err != nil {
		return p.uncatalogued(detail, data)
	}
	return problem.Problem{
		Type:        uri,
		Title:       declared.Title,
		Status:      declared.Status,
		Detail:      &detail,
		Recoverable: declared.Recoverable,
		Data:        data,
	}
}

// uncatalogued produces the C0 §14 uncatalogued fallback: an unknown id or an
// unbuildable type URI is a misconfiguration on the consumer's side, and the
// original failure still has to reach the caller.
func (p *Problems) uncatalogued(detail string, data map[string]any) problem.Problem {
	fallback := problem.FromObject(nil, problem.TransformOptions{
		Portal:         p.registry.Portal(),
		DefaultStatus:  500,
		DefaultVersion: ProblemVersion,
	})
	fallback.Detail = &detail
	fallback.Data = data
	return fallback
}
