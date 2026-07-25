package authengine

import "context"

// OnboardingTokens are the raw token pair a client posts to a backend's
// create-user endpoint when it onboards itself.
//
// The pair travels in the request BODY alongside the normal Authorization
// header: the body proves which identity is being onboarded, the header proves
// who is asking, and the backend requires them to agree.
type OnboardingTokens struct {
	// Access is the raw access token, validated including its audience.
	Access string
	// ID is the raw ID token, validated without the audience check.
	ID string
	// Authorization is the subject taken from the request's own Authorization
	// header. Blank skips the self-onboarding check, which is only correct for a
	// caller that has already proven the header subject some other way.
	Authorization string
}

// OnboardingIdentity is the validated identity a backend registers.
type OnboardingIdentity struct {
	// Subject is the shared `sub` of both tokens.
	Subject string
	// Username is the required username claim.
	Username string
	// Email is the required email claim.
	Email string
	// Access is the principal mapped from the access token.
	Access Principal
	// ID is the principal mapped from the ID token.
	ID Principal
}

// ExtractOnboarding validates both body tokens and returns the identity a
// backend may create a local user row for.
//
// This is the Go realization of the reference stack's token-data extractor, and
// it exists because the create-user endpoint is the one place a service accepts
// tokens as DATA rather than as credentials. It therefore proves four things, in
// order: both tokens fully validate against the JWKS and the baked issuer; the
// two tokens carry the same subject; the ID token carries the username, email,
// and verified-email claims registration needs; and the subject matches the
// caller's own Authorization header. The last check is what makes onboarding
// self-service only — you can never onboard somebody else.
func (v Validator) ExtractOnboarding(ctx context.Context, tokens OnboardingTokens) (OnboardingIdentity, error) {
	access, err := v.Validate(ctx, tokens.Access)
	if err != nil {
		return OnboardingIdentity{}, err
	}
	identity, err := v.ValidateIDToken(ctx, tokens.ID)
	if err != nil {
		return OnboardingIdentity{}, err
	}
	if access.Subject != identity.Subject {
		return OnboardingIdentity{}, v.problems.Raise(ProblemTokenSubjectMismatch,
			"the access token and the ID token do not describe one identity",
			map[string]any{"access": access.Subject, "id": identity.Subject})
	}
	if tokens.Authorization != "" && tokens.Authorization != identity.Subject {
		return OnboardingIdentity{}, v.problems.Raise(ProblemTokenSubjectMismatch,
			"a caller may only onboard its own identity",
			map[string]any{"caller": tokens.Authorization, "body": identity.Subject})
	}
	if identity.Username == nil {
		return OnboardingIdentity{}, v.problems.Raise(ProblemTokenClaimMissing,
			"the ID token carries no username claim",
			map[string]any{"claim": ClaimUsername})
	}
	if identity.Email == nil {
		return OnboardingIdentity{}, v.problems.Raise(ProblemTokenClaimMissing,
			"the ID token carries no email claim",
			map[string]any{"claim": ClaimEmail})
	}
	if !identity.EmailVerified {
		return OnboardingIdentity{}, v.problems.Raise(ProblemTokenClaimMissing,
			"the ID token email is not verified",
			map[string]any{"claim": ClaimEmailVerified})
	}
	return OnboardingIdentity{
		Subject:  identity.Subject,
		Username: *identity.Username,
		Email:    *identity.Email,
		Access:   access,
		ID:       identity,
	}, nil
}
