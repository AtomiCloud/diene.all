package testhelper

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"errors"
	"maps"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	"github.com/golang-jwt/jwt/v5"
)

// Fake IdP defaults. They are realistic rather than minimal so a consumer's
// fixtures look like the real thing: the issuer follows the per-platform identity
// host convention, and the audience is a resource-tree style backend name.
const (
	// DefaultIssuer is the fake IdP's issuer.
	DefaultIssuer = "https://api.lithium.alcohol.mew.cluster.atomi.cloud"
	// DefaultAudience is the fake IdP's access-token audience.
	DefaultAudience = "alcohol-zinc"
	// DefaultKeyID is the fake IdP's signing key id.
	DefaultKeyID = "fake-idp-key-1"
	// DefaultSubject is the fake IdP's default token subject.
	DefaultSubject = "user-1"
	// DefaultKeyBits is the generated signing-key size, matching what a real
	// tenant publishes.
	DefaultKeyBits = 2048
)

// FakeIDPOptions configures a [FakeIDP]. Every field is optional.
type FakeIDPOptions struct {
	// Issuer overrides [DefaultIssuer].
	Issuer string
	// Audience overrides [DefaultAudience].
	Audience string
	// KeyID overrides [DefaultKeyID].
	KeyID string
	// Now fixes the fake clock. Zero uses a fixed, deterministic instant.
	Now time.Time
	// Portal overrides the error portal problems are attributed to.
	Portal *problem.ErrorPortal
	// ExtraProblems registers a consumer's own problem types on the fake's factory,
	// so a suite asserts its domain problems and the engine.s through one registry.
	ExtraProblems []problem.Type
	// KeyBits overrides the generated signing-key size. Zero uses 2048, which is
	// what a real tenant publishes; a large suite may trade strength for speed.
	KeyBits int
}

// TokenRequest describes a token the fake IdP should mint.
//
// The deliberately wrong-looking fields — Issuer, Audience, KeyID, ExpiresAt — are
// how a consumer reaches the failure branches of its own validation code. A test
// that can only mint valid tokens cannot prove that an expired one is rejected.
type TokenRequest struct {
	// Subject overrides [DefaultSubject].
	Subject string
	// Username sets the username claim; blank omits it.
	Username string
	// Email sets the email claim; blank omits it.
	Email string
	// EmailUnverified emits email_verified=false instead of true.
	EmailUnverified bool
	// Roles sets the roles claim.
	Roles []string
	// Scopes sets the space-delimited scope claim.
	Scopes []string
	// HomeLandscape sets the home-landscape claim; blank omits it.
	HomeLandscape string
	// Registered names the backends whose registration claim is emitted as true.
	Registered []string
	// Claims are extra claims merged in last, so a test can emit anything.
	Claims map[string]any
	// Issuer overrides the fake IdP's issuer, to mint an untrusted token.
	Issuer string
	// Audience overrides the fake IdP's audience, to mint a mis-audienced token.
	Audience string
	// KeyID overrides the signing key id, to mint a token with an unknown key.
	KeyID string
	// ExpiresAt overrides the expiry, to mint an expired token.
	ExpiresAt time.Time
	// OmitExpiry omits the exp claim entirely.
	OmitExpiry bool
	// OmitKeyID omits the kid header entirely, which is how a consumer proves its
	// key resolver refuses to guess a key rather than picking the only one it has.
	OmitKeyID bool
}

// FakeIDP is an in-memory identity provider that signs real RS256 tokens.
//
// It is not a mock of the JWT library: the tokens it mints are genuinely signed and
// genuinely verified, so a consumer's validator, key resolution, algorithm
// restriction, and claim mapping all run for real. What is faked is only the
// network and the tenant.
type FakeIDP struct {
	issuer   string
	audience string
	keyID    string
	key      *rsa.PrivateKey
	clock    *mocks.InMemorySystem
	problems *authengine.Problems
}

// NewFakeIDP creates a fake identity provider with a freshly generated signing key.
//
// The key is 2048-bit because that is what a real tenant publishes; generating it
// per instance keeps suites independent, and it costs a few milliseconds once.
func NewFakeIDP(options FakeIDPOptions) (*FakeIDP, error) {
	bits := options.KeyBits
	if bits == 0 {
		bits = DefaultKeyBits
	}
	key, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		return nil, err
	}
	portal := SampleErrorPortal()
	if options.Portal != nil {
		portal = *options.Portal
	}
	problems, err := authengine.NewProblems(portal, options.ExtraProblems...)
	if err != nil {
		return nil, err
	}
	now := options.Now
	if now.IsZero() {
		now = FixedNow()
	}
	return &FakeIDP{
		issuer:   orDefault(options.Issuer, DefaultIssuer),
		audience: orDefault(options.Audience, DefaultAudience),
		keyID:    orDefault(options.KeyID, DefaultKeyID),
		key:      key,
		clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: now}),
		problems: problems,
	}, nil
}

// Issuer returns the issuer this fake mints for.
func (f *FakeIDP) Issuer() string {
	return f.issuer
}

// Audience returns the access-token audience this fake mints for.
func (f *FakeIDP) Audience() string {
	return f.audience
}

// Problems returns the problem factory bound to this fake's error portal, so a
// consumer's own engine components share one portal with the fake.
func (f *FakeIDP) Problems() *authengine.Problems {
	return f.problems
}

// Clock returns the fake's injectable clock seam.
func (f *FakeIDP) Clock() *mocks.InMemorySystem {
	return f.clock
}

// Advance moves the fake clock forward, which is how a test crosses a token's
// expiry boundary without sleeping.
func (f *FakeIDP) Advance(by time.Duration) {
	now, _ := f.clock.NowUTC()
	next := now.Add(by)
	f.clock.SetNow(next)
}

// Keys returns a [authengine.VerificationKeys] publishing this fake's public key.
func (f *FakeIDP) Keys() authengine.VerificationKeys {
	return fakeKeys{keyID: f.keyID, key: &f.key.PublicKey}
}

// Validator returns a validator wired to this fake: its issuer, its audience, its
// key, and its clock.
func (f *FakeIDP) Validator() (authengine.Validator, error) {
	return authengine.NewValidator(authengine.ValidatorOptions{
		Issuer:   f.issuer,
		Audience: f.audience,
		Keys:     f.Keys(),
		Problems: f.problems,
		Clock:    f.clock,
	})
}

// Guard returns an ownership guard sharing this fake's problem factory.
func (f *FakeIDP) Guard() (authengine.Guard, error) {
	return authengine.NewGuard(authengine.GuardOptions{Problems: f.problems})
}

// MintAccessToken signs an access token from request.
func (f *FakeIDP) MintAccessToken(request TokenRequest) (string, error) {
	return f.mint(request, orDefault(request.Audience, f.audience))
}

// MintIDToken signs an ID token from request.
//
// An ID token is minted for the CLIENT rather than for a resource server, so its
// audience is deliberately different from the access token's — which is exactly the
// asymmetry a consumer's ID-token validation has to tolerate.
func (f *FakeIDP) MintIDToken(request TokenRequest) (string, error) {
	return f.mint(request, orDefault(request.Audience, "fake-idp-client"))
}

// mint signs one token with the requested claims and audience.
func (f *FakeIDP) mint(request TokenRequest, audience string) (string, error) {
	now, err := f.clock.NowUTC()
	if err != nil {
		return "", err
	}
	claims := jwt.MapClaims{
		authengine.ClaimSubject:  orDefault(request.Subject, DefaultSubject),
		authengine.ClaimIssuer:   orDefault(request.Issuer, f.issuer),
		authengine.ClaimAudience: audience,
		"iat":                    now.Unix(),
	}
	if !request.OmitExpiry {
		expiry := request.ExpiresAt
		if expiry.IsZero() {
			expiry = now.Add(authengine.AccessTokenLifetime)
		}
		claims[authengine.ClaimExpiry] = expiry.Unix()
	}
	if request.Username != "" {
		claims[authengine.ClaimUsername] = request.Username
	}
	if request.Email != "" {
		claims[authengine.ClaimEmail] = request.Email
		claims[authengine.ClaimEmailVerified] = !request.EmailUnverified
	}
	if len(request.Roles) > 0 {
		claims[authengine.ClaimRoles] = toAny(request.Roles)
	}
	if len(request.Scopes) > 0 {
		claims[authengine.ClaimScope] = joinScopes(request.Scopes)
	}
	if request.HomeLandscape != "" {
		claims[authengine.ClaimHomeLandscape] = request.HomeLandscape
	}
	for _, backend := range request.Registered {
		claims[authengine.RegistrationClaim(backend)] = "true"
	}
	maps.Copy(claims, request.Claims)

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	if !request.OmitKeyID {
		token.Header[HeaderKeyID] = orDefault(request.KeyID, f.keyID)
	}
	return token.SignedString(f.key)
}

// HeaderKeyID is the JOSE header naming the signing key.
const HeaderKeyID = "kid"

// fakeKeys publishes exactly one key id, so a request for any other key id fails
// the way a real JWKS miss does.
type fakeKeys struct {
	keyID string
	key   crypto.PublicKey
}

// Key returns the published key for keyID.
func (k fakeKeys) Key(_ context.Context, keyID string) (crypto.PublicKey, error) {
	if keyID != k.keyID {
		return nil, errors.New("fake IdP publishes no key " + keyID)
	}
	return k.key, nil
}
