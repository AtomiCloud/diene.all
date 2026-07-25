package authengine_test

import (
	"context"
	"errors"
	"fmt"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func ExampleClaims_Flag() {
	claims := authengine.Claims{"alcohol_zinc": "true"}

	registered, present := claims.Flag("alcohol_zinc")
	fmt.Println(registered, present)

	// An absent registration claim is not a false one: only the absent case
	// enters the onboarding phase machine.
	_, present = authengine.Claims{}.Flag("alcohol_zinc")
	fmt.Println(present)
	// Output:
	// true true
	// false
}

func ExampleClaims_Space() {
	claims := authengine.Claims{authengine.ClaimScope: "read:booking write:booking"}

	scopes, _ := claims.Space(authengine.ClaimScope)
	fmt.Println(scopes)
	// Output: [read:booking write:booking]
}

func ExampleAccessTokenLifetime() {
	fmt.Println(authengine.AccessTokenLifetime, authengine.RefreshTokenLifetime)
	// Output: 10m0s 336h0m0s
}

func ExampleValidator_Validate() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	validator, _ := idp.Validator()

	token, _ := idp.MintAccessToken(testhelper.TokenRequest{Subject: "user-1", Roles: []string{"admin"}})

	principal, err := validator.Validate(context.Background(), token)
	if err != nil {
		// Every auth failure is an RFC 9457 envelope: recover it with errors.As.
		var pe *problem.Error
		if errors.As(err, &pe) {
			fmt.Println(pe.Problem.Status)
		}
		return
	}
	fmt.Println(principal.Subject, principal.HasRole("admin"))
	// Output: user-1 true
}

func ExampleGuard_SubOrAny() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	guard, _ := idp.Guard()

	owner := authengine.NewClaimMapper().Map(authengine.Claims{authengine.ClaimSubject: "user-1"})
	admin := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "staff-1",
		authengine.ClaimRoles:   []any{"admin"},
	})
	target := "user-1"
	other := "user-2"

	// Owner passes its OWN userId; admin OMITS it; an attacker names somebody else.
	fmt.Println(guard.SubOrAny(owner, &target, authengine.ClaimRoles, "admin") == nil)
	fmt.Println(guard.SubOrAny(admin, nil, authengine.ClaimRoles, "admin") == nil)
	fmt.Println(guard.SubOrAny(owner, &other, authengine.ClaimRoles, "admin") == nil)
	// Output:
	// true
	// true
	// false
}

func ExampleGuard_Registered() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	guard, _ := idp.Guard()

	onboarded := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-1",
		"alcohol_zinc":          "true",
	})

	fmt.Println(guard.Registered(onboarded, "alcohol-zinc") == nil)
	fmt.Println(guard.Registered(onboarded, "nitroso-tin") == nil)
	// Output:
	// true
	// false
}

func ExampleRegistrationClaim() {
	fmt.Println(authengine.RegistrationClaim("alcohol-zinc"))
	// Output: alcohol_zinc
}

func ExampleTokenCache_All() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	problems := idp.Problems()
	tree, _ := authengine.NewResourceTree(
		problems,
		authengine.Resource{Name: "alcohol-zinc", Indicator: "https://api.zinc.invalid"},
		authengine.Resource{Name: "nitroso-tin", Indicator: "https://api.tin.invalid"},
	)

	cache, _ := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    testhelper.NewMemoryTokenStore(),
		Source:   authengine.NewClientCredentialsSource(testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})),
		Problems: problems,
		Clock:    idp.Clock(),
	})

	// Onboarding batches every backend eagerly rather than lazily on first call.
	tokens, _ := cache.All(context.Background())
	fmt.Println(len(tokens), tokens["alcohol-zinc"].Resource)
	// Output: 2 alcohol-zinc
}

func ExampleConfigBlockKey() {
	// A service composes one block per engine into its root schema; the CONFIG
	// library is the sole merger and validator.
	schema := map[string]any{
		authengine.ConfigBlockKey: authengine.ConfigBlockSchema(),
	}
	fmt.Println(authengine.ConfigBlockKey, schema[authengine.ConfigBlockKey].(map[string]any)["type"])
	// Output: auth object
}
