package authengine_test

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
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
