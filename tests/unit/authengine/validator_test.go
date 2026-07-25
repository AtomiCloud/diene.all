package authengine_test

import (
	"context"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

func TestNewValidatorRejectsAnIncompleteConfiguration(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	keys := newIDP(t).Keys()
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{})

	if _, err := authengine.NewValidator(authengine.ValidatorOptions{}); err == nil {
		t.Fatal("expected a validator without a problem factory to be rejected")
	}

	cases := []struct {
		name    string
		options authengine.ValidatorOptions
	}{
		{
			name:    "blank issuer",
			options: authengine.ValidatorOptions{Problems: problems, Keys: keys, Clock: clock},
		},
		{
			name: "no key source",
			options: authengine.ValidatorOptions{
				Problems: problems, Issuer: testhelper.DefaultIssuer, Clock: clock,
			},
		},
		{
			name: "no clock",
			options: authengine.ValidatorOptions{
				Problems: problems, Issuer: testhelper.DefaultIssuer, Keys: keys,
			},
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			_, err := authengine.NewValidator(testCase.options)
			requireProblem(t, err, authengine.ProblemConfigInvalid)
		})
	}
}

func TestValidateMapsAValidAccessToken(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{
		Subject: "user-1",
		Roles:   []string{"admin"},
		Scopes:  []string{"read:booking"},
	})
	requireNoError(t, err)

	principal, err := validator.Validate(context.Background(), token)
	requireNoError(t, err)

	if principal.Subject != "user-1" {
		t.Fatalf("expected subject user-1, got %q", principal.Subject)
	}
	if !principal.HasRole("admin") || !principal.HasScope("read:booking") {
		t.Fatalf("expected roles and scopes to be mapped, got %+v", principal)
	}
	if validator.Issuer() != idp.Issuer() {
		t.Fatalf("expected the baked issuer %q, got %q", idp.Issuer(), validator.Issuer())
	}
}

func TestValidateRejectsEveryDistinctFailureWithItsOwnProblem(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		request testhelper.TokenRequest
		want    string
	}{
		{
			name:    "untrusted issuer",
			request: testhelper.TokenRequest{Issuer: "https://evil.invalid"},
			want:    authengine.ProblemTokenIssuerMismatch,
		},
		{
			name:    "wrong audience",
			request: testhelper.TokenRequest{Audience: "someone-else"},
			want:    authengine.ProblemTokenAudienceMismatch,
		},
		{
			name:    "unknown signing key",
			request: testhelper.TokenRequest{KeyID: "rotated-away"},
			want:    authengine.ProblemSigningKeyUnknown,
		},
		{
			name:    "no expiry",
			request: testhelper.TokenRequest{OmitExpiry: true},
			want:    authengine.ProblemTokenMalformed,
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			idp := newIDP(t)
			validator, err := idp.Validator()
			requireNoError(t, err)

			token, err := idp.MintAccessToken(testCase.request)
			requireNoError(t, err)

			_, err = validator.Validate(context.Background(), token)
			requireProblem(t, err, testCase.want)
		})
	}
}

func TestValidateRejectsABlankToken(t *testing.T) {
	t.Parallel()

	validator, err := newIDP(t).Validator()
	requireNoError(t, err)

	_, err = validator.Validate(context.Background(), "")
	requireProblem(t, err, authengine.ProblemTokenMalformed)
}

func TestValidateRejectsAGarbageToken(t *testing.T) {
	t.Parallel()

	validator, err := newIDP(t).Validator()
	requireNoError(t, err)

	_, err = validator.Validate(context.Background(), "not-a-jwt")
	requireProblem(t, err, authengine.ProblemTokenMalformed)
}

func TestValidateRejectsATokenSignedByAnotherKey(t *testing.T) {
	t.Parallel()

	trusted := newIDP(t)
	// A second IdP publishing the SAME key id: every claim validates and the key
	// resolves, so only the signature check can catch this. That is the shape of a
	// real key-substitution attempt.
	impostor, err := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{
		Issuer:   trusted.Issuer(),
		Audience: trusted.Audience(),
		KeyID:    testhelper.DefaultKeyID,
	})
	requireNoError(t, err)

	validator, err := trusted.Validator()
	requireNoError(t, err)

	token, err := impostor.MintAccessToken(testhelper.TokenRequest{})
	requireNoError(t, err)

	_, err = validator.Validate(context.Background(), token)
	requireProblem(t, err, authengine.ProblemTokenSignatureInvalid)
}

func TestValidateRejectsAKeyIDLessToken(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{KeyID: " "})
	requireNoError(t, err)

	// A blank kid is not a kid: the key resolver must refuse rather than pick a key.
	_, err = validator.Validate(context.Background(), token)
	requireProblem(t, err, authengine.ProblemSigningKeyUnknown)
}

func TestValidateHonoursTheExpiryBoundaryOnTheInjectedClock(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := authengine.NewValidator(authengine.ValidatorOptions{
		Issuer:   idp.Issuer(),
		Audience: idp.Audience(),
		Keys:     idp.Keys(),
		Problems: idp.Problems(),
		Clock:    idp.Clock(),
		// No leeway: the boundary is exactly the expiry instant.
		Leeway: time.Nanosecond,
	})
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{})
	requireNoError(t, err)

	_, err = validator.Validate(context.Background(), token)
	requireNoError(t, err)

	idp.Advance(authengine.AccessTokenLifetime + time.Second)

	_, err = validator.Validate(context.Background(), token)
	requireProblem(t, err, authengine.ProblemTokenExpired)
}

func TestValidateAcceptsAnExpiredTokenInsideTheLeeway(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{})
	requireNoError(t, err)

	// Just inside the default clock skew: issuer/verifier drift must not log a user
	// out a second early.
	idp.Advance(authengine.AccessTokenLifetime + authengine.DefaultClockSkew/2)

	_, err = validator.Validate(context.Background(), token)
	requireNoError(t, err)
}

func TestValidateRejectsAnUnlistedAlgorithm(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := authengine.NewValidator(authengine.ValidatorOptions{
		Issuer:     idp.Issuer(),
		Audience:   idp.Audience(),
		Keys:       idp.Keys(),
		Problems:   idp.Problems(),
		Clock:      idp.Clock(),
		Algorithms: []string{"ES256"},
	})
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{})
	requireNoError(t, err)

	_, err = validator.Validate(context.Background(), token)
	requireProblem(t, err, authengine.ProblemTokenSignatureInvalid)
}

func TestDefaultAlgorithmsExcludeSymmetricSigning(t *testing.T) {
	t.Parallel()

	for _, algorithm := range authengine.DefaultAlgorithms {
		if algorithm[0] == 'H' {
			t.Fatalf("a JWKS-verified token must never accept the symmetric %q", algorithm)
		}
	}
}

func TestValidateSurfacesAClockFailure(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{})
	requireNoError(t, err)

	idp.Clock().EnqueueClockResult(time.Time{}, errFake)

	_, err = validator.Validate(context.Background(), token)
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestValidateIDTokenSkipsTheAudienceCheckOnly(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	identity, err := idp.MintIDToken(testhelper.TokenRequest{Subject: "user-1"})
	requireNoError(t, err)

	// The same token is rejected as an access token (wrong audience) and accepted as
	// an ID token: the asymmetry is deliberate, not an oversight.
	if _, rejected := validator.Validate(context.Background(), identity); rejected == nil {
		t.Fatal("expected an ID token to fail the access-token audience check")
	}
	principal, err := validator.ValidateIDToken(context.Background(), identity)
	requireNoError(t, err)
	if principal.Subject != "user-1" {
		t.Fatalf("expected subject user-1, got %q", principal.Subject)
	}

	// Every other check still applies.
	expired, err := idp.MintIDToken(testhelper.TokenRequest{ExpiresAt: idpPast(idp)})
	requireNoError(t, err)
	_, err = validator.ValidateIDToken(context.Background(), expired)
	requireProblem(t, err, authengine.ProblemTokenExpired)
}

// idpPast returns an instant well before the fake IdP's clock.
func idpPast(idp *testhelper.FakeIDP) time.Time {
	now, _ := idp.Clock().NowUTC()
	return now.Add(-24 * time.Hour)
}

func TestValidateRefusesATokenWithNoKeyIDHeader(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	token, err := idp.MintAccessToken(testhelper.TokenRequest{OmitKeyID: true})
	requireNoError(t, err)

	// With one published key it would be tempting to just use it; refusing keeps the
	// key-substitution surface closed.
	_, err = validator.Validate(context.Background(), token)
	requireProblem(t, err, authengine.ProblemSigningKeyUnknown)
}
