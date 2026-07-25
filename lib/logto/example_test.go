package logto_test

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/logto"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
)

func ExampleNewClient() {
	tenant := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writer.Header().Set("Content-Type", "application/json")
		_, _ = writer.Write([]byte(`{"access_token":"m2m","expires_in":600}`))
	}))
	defer tenant.Close()

	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	client, _ := logto.NewClient(logto.ClientOptions{
		Config: authengine.Config{Minting: authengine.MintingConfig{
			TokenEndpoint: tenant.URL + "/oidc/token",
			ClientID:      "operator",
		}},
		Problems: idp.Problems(),
		Clock:    idp.Clock(),
	})

	// The operator's machine-to-machine flow: no user session to impersonate.
	token, err := client.ClientCredentials(context.Background(), authengine.ClientCredentialsRequest{
		Resource: authengine.Resource{Name: "alcohol-zinc", Indicator: "https://api.zinc.invalid"},
	})
	fmt.Println(token.Value, token.Resource, err == nil)

	// The provider's relative expires_in becomes an absolute instant off the
	// injected clock, so caching decisions stay testable.
	fmt.Println(token.ExpiresAt.Sub(testhelper.FixedNow()))
	// Output:
	// m2m alcohol-zinc true
	// 10m0s
}

func ExampleNewRemoteJWKS() {
	// A misconfigured JWKS URI fails at startup rather than on the first request
	// that needs a key.
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})

	_, err := logto.NewRemoteJWKS(context.Background(), "", idp.Problems())
	fmt.Println(err != nil)
	// Output: true
}
