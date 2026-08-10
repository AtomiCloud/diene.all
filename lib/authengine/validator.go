package authengine

import (
	"context"
	"crypto"
	"errors"
	"slices"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/golang-jwt/jwt/v5"
)

// VerificationKeys resolves JWT verification keys by key id.
//
// It is the seam the IdP's JWKS endpoint sits behind. Production binds
// logto.NewRemoteJWKS, whose fetch caching and refresh are the JWKS library's
// defaults (no family-wide minimum lifetime is mandated); tests bind the shipped
// in-memory fake and never touch a network.
type VerificationKeys interface {
	// Key returns the public verification key published for keyID. A key id the
	// set does not publish must return an error rather than a nil key.
	Key(ctx context.Context, keyID string) (crypto.PublicKey, error)
}

// DefaultAlgorithms are the signing algorithms accepted when a validator does
// not narrow them. Symmetric algorithms are deliberately absent: a JWKS-verified
// token is asymmetric by construction, and accepting HS256 alongside RS256 is
// the classic key-confusion foothold.
var DefaultAlgorithms = []string{"RS256", "RS384", "RS512", "ES256", "ES384", "ES512"}

// ValidatorOptions configures a [Validator].
type ValidatorOptions struct {
	// Issuer is the expected `iss` claim. It is BAKED build-time configuration:
	// it must never be sourced from a document fetched at runtime.
	Issuer string
	// Audience is the expected `aud` claim for access tokens.
	Audience string
	// Keys resolves JWKS verification keys.
	Keys VerificationKeys
	// Problems mints the problem-typed validation failures.
	Problems *Problems
	// Clock is the injected time seam; validation never reads the wall clock
	// directly, which is what makes expiry-boundary tests deterministic.
	Clock interfaces.System
	// Mapper maps a validated claim set onto a Principal. The zero value uses
	// the family defaults.
	Mapper ClaimMapper
	// Leeway absorbs clock drift between issuer and verifier. Zero uses
	// [DefaultClockSkew].
	Leeway time.Duration
	// Algorithms narrows the accepted signing algorithms. Empty uses
	// [DefaultAlgorithms].
	Algorithms []string
}

// Validator validates JWTs against a baked OIDC issuer and the IdP's JWKS.
//
// Validation is complete rather than partial: signature against the JWKS key for
// the token's `kid`, the registered algorithm set, issuer, expiry with leeway,
// and — for access tokens — audience. Each distinct failure surfaces as its own
// problem id so a consumer can tell "your token aged out" from "your token was
// minted somewhere we do not trust".
type Validator struct {
	issuer     string
	audience   string
	keys       VerificationKeys
	problems   *Problems
	clock      interfaces.System
	mapper     ClaimMapper
	leeway     time.Duration
	algorithms []string
}

// NewValidator creates a validator from options, rejecting a configuration it
// cannot honour: a blank issuer, a missing key source, a missing problem
// factory, or a missing clock seam.
func NewValidator(options ValidatorOptions) (Validator, error) {
	if options.Problems == nil {
		return Validator{}, errors.New("auth-engine validator requires a problem factory")
	}
	if options.Issuer == "" {
		return Validator{}, options.Problems.Raise(ProblemConfigInvalid,
			"the OIDC issuer is baked build-time configuration and must not be blank", nil)
	}
	if options.Keys == nil {
		return Validator{}, options.Problems.Raise(ProblemConfigInvalid,
			"a JWKS verification key source is required", nil)
	}
	if options.Clock == nil {
		return Validator{}, options.Problems.Raise(ProblemConfigInvalid,
			"a clock seam is required so token expiry stays injectable", nil)
	}
	mapper := options.Mapper
	if mapper == (ClaimMapper{}) {
		mapper = NewClaimMapper()
	}
	leeway := options.Leeway
	if leeway == 0 {
		leeway = DefaultClockSkew
	}
	algorithms := options.Algorithms
	if len(algorithms) == 0 {
		algorithms = DefaultAlgorithms
	}
	return Validator{
		issuer:     options.Issuer,
		audience:   options.Audience,
		keys:       options.Keys,
		problems:   options.Problems,
		clock:      options.Clock,
		mapper:     mapper,
		leeway:     leeway,
		algorithms: slices.Clone(algorithms),
	}, nil
}

// Issuer returns the baked issuer this validator trusts.
func (v Validator) Issuer() string {
	return v.issuer
}

// Validate fully validates an access token and maps it onto a [Principal],
// including the audience check.
func (v Validator) Validate(ctx context.Context, token string) (Principal, error) {
	return v.parse(ctx, token, v.audience)
}

// ValidateIDToken fully validates an ID token and maps it onto a [Principal].
//
// The audience check is deliberately skipped: an ID token is minted for the
// client application rather than for the resource server reading it, so
// enforcing the resource audience here would reject every legitimate token. Every
// other check — signature, algorithm, issuer, expiry — still applies.
func (v Validator) ValidateIDToken(ctx context.Context, token string) (Principal, error) {
	return v.parse(ctx, token, "")
}

// parse runs the full validation chain. A blank audience skips the audience
// check; every other check always runs.
func (v Validator) parse(ctx context.Context, token string, audience string) (Principal, error) {
	if token == "" {
		return Principal{}, v.problems.Raise(ProblemTokenMalformed, "the bearer token is blank", nil)
	}
	now, err := v.clock.NowUTC()
	if err != nil {
		return Principal{}, v.problems.RaiseFrom(ProblemProviderUnavailable, err,
			"the clock seam could not supply the current instant", nil)
	}

	options := []jwt.ParserOption{
		jwt.WithValidMethods(v.algorithms),
		jwt.WithIssuer(v.issuer),
		jwt.WithLeeway(v.leeway),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(func() time.Time { return now }),
	}
	if audience != "" {
		options = append(options, jwt.WithAudience(audience))
	}

	claims := jwt.MapClaims{}
	if _, err := jwt.NewParser(options...).ParseWithClaims(token, claims, v.keyfunc(ctx)); err != nil {
		return Principal{}, v.classify(err)
	}
	return v.mapper.Map(Claims(claims)), nil
}

// keyfunc resolves the verification key for the token's `kid` header through the
// injected key source.
func (v Validator) keyfunc(ctx context.Context) jwt.Keyfunc {
	return func(token *jwt.Token) (any, error) {
		keyID, found := token.Header[jwkKeyIDHeader].(string)
		if !found || keyID == "" {
			return nil, v.problems.Raise(ProblemSigningKeyUnknown,
				"the token header carries no key id", nil)
		}
		key, err := v.keys.Key(ctx, keyID)
		if err != nil {
			return nil, v.problems.RaiseFrom(ProblemSigningKeyUnknown, err,
				"the JWKS publishes no key for the token key id",
				map[string]any{"keyId": keyID})
		}
		return key, nil
	}
}

// jwkKeyIDHeader is the JOSE header naming the JWKS key that signed a token.
const jwkKeyIDHeader = "kid"

// classify maps a JWT library failure onto the engine's problem vocabulary. The
// order matters: expiry is checked before the generic invalid-claims case so an
// aged-out token reports as recoverable rather than as a hard rejection.
func (v Validator) classify(err error) error {
	var carried *problem.Error
	switch {
	case errors.As(err, &carried):
		// The key resolver already raised a problem-typed failure; the JWT
		// library only wrapped it, so surface the original rather than
		// reclassifying a key-resolution failure as a malformed token.
		return carried
	case errors.Is(err, jwt.ErrTokenExpired):
		return v.problems.RaiseFrom(ProblemTokenExpired, err, "the token lifetime has elapsed", nil)
	case errors.Is(err, jwt.ErrTokenInvalidIssuer):
		return v.problems.RaiseFrom(ProblemTokenIssuerMismatch, err,
			"the token was not minted by the trusted issuer",
			map[string]any{"expected": v.issuer})
	case errors.Is(err, jwt.ErrTokenInvalidAudience):
		return v.problems.RaiseFrom(ProblemTokenAudienceMismatch, err,
			"the token was not minted for this audience",
			map[string]any{"expected": v.audience})
	case errors.Is(err, jwt.ErrTokenSignatureInvalid):
		return v.problems.RaiseFrom(ProblemTokenSignatureInvalid, err,
			"the token signature does not verify against the published key", nil)
	default:
		return v.problems.RaiseFrom(ProblemTokenMalformed, err, "the token could not be parsed", nil)
	}
}
