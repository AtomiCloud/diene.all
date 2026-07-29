package authengine_test

import (
	"context"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
)

// onboardingTokens mints a matched, fully claimed token pair for subject.
func onboardingTokens(t *testing.T, idp *testhelper.FakeIDP, subject string) authengine.OnboardingTokens {
	t.Helper()

	request := testhelper.TokenRequest{
		Subject:  subject,
		Username: "owner",
		Email:    "owner@example.invalid",
	}
	access, err := idp.MintAccessToken(request)
	requireNoError(t, err)
	identity, err := idp.MintIDToken(request)
	requireNoError(t, err)
	return authengine.OnboardingTokens{Access: access, ID: identity, Authorization: subject}
}

func TestExtractOnboardingAcceptsAMatchedPair(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	identity, err := validator.ExtractOnboarding(context.Background(), onboardingTokens(t, idp, "user-1"))
	requireNoError(t, err)

	if identity.Subject != "user-1" {
		t.Fatalf("expected subject user-1, got %q", identity.Subject)
	}
	if identity.Username != "owner" || identity.Email != "owner@example.invalid" {
		t.Fatalf("expected the registration claims to be extracted, got %+v", identity)
	}
	if identity.Access.Subject != identity.ID.Subject {
		t.Fatal("expected both principals to describe one identity")
	}
}

func TestExtractOnboardingRefusesToOnboardSomebodyElse(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	tokens := onboardingTokens(t, idp, "user-1")
	tokens.Authorization = "user-2"

	_, err = validator.ExtractOnboarding(context.Background(), tokens)
	requireProblem(t, err, authengine.ProblemTokenSubjectMismatch)
}

func TestExtractOnboardingRefusesAMismatchedPair(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	tokens := onboardingTokens(t, idp, "user-1")
	other := onboardingTokens(t, idp, "user-2")
	tokens.ID = other.ID
	tokens.Authorization = ""

	_, err = validator.ExtractOnboarding(context.Background(), tokens)
	requireProblem(t, err, authengine.ProblemTokenSubjectMismatch)
}

func TestExtractOnboardingSkipsTheSelfCheckForABlankHeader(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	tokens := onboardingTokens(t, idp, "user-1")
	tokens.Authorization = ""

	identity, err := validator.ExtractOnboarding(context.Background(), tokens)
	requireNoError(t, err)
	if identity.Subject != "user-1" {
		t.Fatalf("expected subject user-1, got %q", identity.Subject)
	}
}

func TestExtractOnboardingRequiresTheRegistrationClaims(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		request testhelper.TokenRequest
	}{
		{name: "no username", request: testhelper.TokenRequest{Email: "owner@example.invalid"}},
		{name: "no email", request: testhelper.TokenRequest{Username: "owner"}},
		{
			name: "unverified email",
			request: testhelper.TokenRequest{
				Username:        "owner",
				Email:           "owner@example.invalid",
				EmailUnverified: true,
			},
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			idp := newIDP(t)
			validator, err := idp.Validator()
			requireNoError(t, err)

			request := testCase.request
			request.Subject = "user-1"
			access, err := idp.MintAccessToken(request)
			requireNoError(t, err)
			identity, err := idp.MintIDToken(request)
			requireNoError(t, err)

			_, err = validator.ExtractOnboarding(context.Background(), authengine.OnboardingTokens{
				Access: access, ID: identity,
			})
			requireProblem(t, err, authengine.ProblemTokenClaimMissing)
		})
	}
}

func TestExtractOnboardingRejectsEitherInvalidToken(t *testing.T) {
	t.Parallel()

	idp := newIDP(t)
	validator, err := idp.Validator()
	requireNoError(t, err)

	valid := onboardingTokens(t, idp, "user-1")

	_, err = validator.ExtractOnboarding(context.Background(), authengine.OnboardingTokens{
		Access: "not-a-jwt", ID: valid.ID,
	})
	requireProblem(t, err, authengine.ProblemTokenMalformed)

	_, err = validator.ExtractOnboarding(context.Background(), authengine.OnboardingTokens{
		Access: valid.Access, ID: "not-a-jwt",
	})
	requireProblem(t, err, authengine.ProblemTokenMalformed)
}
