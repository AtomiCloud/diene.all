package testhelper_test

import (
	"context"
	"fmt"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
)

func ExampleNewFakeIDP() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	validator, _ := idp.Validator()

	// The tokens are really signed and really verified: only the network and the
	// tenant are faked.
	token, _ := idp.MintAccessToken(testhelper.TokenRequest{Subject: "user-1", Roles: []string{"admin"}})
	principal, err := validator.Validate(context.Background(), token)
	fmt.Println(principal.Subject, principal.HasRole("admin"), err == nil)

	// Advancing the clock reaches the expiry branch without a sleep.
	idp.Advance(authengine.AccessTokenLifetime + authengine.DefaultClockSkew + 1)
	_, err = validator.Validate(context.Background(), token)
	fmt.Println(err != nil)
	// Output:
	// user-1 true true
	// true
}

func ExampleAssertAuthProblem() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	guard, _ := idp.Guard()

	owner := authengine.NewClaimMapper().Map(authengine.Claims{authengine.ClaimSubject: "user-1"})
	other := "user-2"

	// Matching on the id keeps a test portable: the full type URI embeds the
	// consumer's own landscape, platform, service, and module.
	envelope, failure := testhelper.CheckAuthProblem(
		guard.Sub(owner, &other), authengine.ProblemOwnershipDenied,
	)
	fmt.Println(envelope.Status, failure == nil)
	// Output: 403 true
}
