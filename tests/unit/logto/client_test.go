package logto_test

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/logto"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	mocks "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// errFake is the transport failure the doubles raise.
var errFake = errors.New("scripted failure")

// resource is the backend tokens are minted for.
var resource = authengine.Resource{
	Name:      "alcohol-zinc",
	Indicator: "https://api.zinc.invalid",
	Scopes:    []string{"read:booking"},
}

// tenant is a stub Logto tenant recording what the adapter sent.
type tenant struct {
	server   *httptest.Server
	requests []recorded
}

// recorded is one captured request.
type recorded struct {
	method string
	path   string
	body   string
	auth   string
}

// newTenant serves the token endpoint and the management API from one host,
// returning whatever the handler decides — which is how the failure paths become
// reachable without a live provider.
func newTenant(t *testing.T, handler func(http.ResponseWriter, *http.Request)) *tenant {
	t.Helper()

	stub := &tenant{}
	stub.server = httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		body, _ := io.ReadAll(request.Body)
		stub.requests = append(stub.requests, recorded{
			method: request.Method,
			path:   request.URL.Path,
			body:   string(body),
			auth:   request.Header.Get("Authorization"),
		})
		handler(writer, request)
	}))
	t.Cleanup(stub.server.Close)
	return stub
}

// config points the adapter at the stub tenant.
func (s *tenant) config() authengine.Config {
	return authengine.Config{
		IDP: authengine.IDPConfig{
			Issuer: s.server.URL,
			Management: authengine.ManagementConfig{
				Endpoint: s.server.URL + "/",
				Resource: "https://management.invalid",
			},
		},
		Minting: authengine.MintingConfig{
			TokenEndpoint: s.server.URL + "/oidc/token",
			ClientID:      "zinc",
			ClientSecret:  "shhh",
		},
	}
}

// newClient wires the adapter against config.
func newClient(t *testing.T, config authengine.Config, transport logto.Doer) logto.Client {
	t.Helper()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	client, err := logto.NewClient(logto.ClientOptions{
		Config:   config,
		HTTP:     transport,
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()}),
	})
	requireNoError(t, err)
	return client
}

func requireNoError(t *testing.T, err error) {
	t.Helper()

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func requireProblem(t *testing.T, err error, id string) {
	t.Helper()

	if _, failure := testhelper.CheckAuthProblem(err, id); failure != nil {
		t.Fatalf("%v", failure)
	}
}

// grant writes a Logto token response.
func grant(writer http.ResponseWriter, body string) {
	writer.Header().Set("Content-Type", "application/json")
	_, _ = io.WriteString(writer, body)
}

func TestNewClientRejectsAnIncompleteConfiguration(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{})

	if _, missing := logto.NewClient(logto.ClientOptions{}); missing == nil {
		t.Fatal("expected a client without a problem factory to be rejected")
	}
	_, err = logto.NewClient(logto.ClientOptions{Problems: problems})
	requireProblem(t, err, authengine.ProblemConfigInvalid)

	_, err = logto.NewClient(logto.ClientOptions{Problems: problems, Clock: clock})
	requireProblem(t, err, authengine.ProblemConfigInvalid)
}

func TestNewClientDefaultsItsTransport(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)

	_, err = logto.NewClient(logto.ClientOptions{
		Config:   authengine.Config{Minting: authengine.MintingConfig{TokenEndpoint: "https://idp.invalid/token"}}, //nolint:gosec // an endpoint URL, not a credential
		Problems: problems,
		Clock:    mocks.NewInMemorySystem(mocks.InMemorySystemOptions{}),
	})
	requireNoError(t, err)
}

func TestResourceTokenExchangesTheRefreshToken(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"minted","expires_in":600,"scope":"read:booking write:booking"}`)
	})
	client := newClient(t, stub.config(), nil)

	token, err := client.ResourceToken(context.Background(), authengine.ResourceTokenRequest{
		Subject: "user-1", RefreshToken: "refresh-1", Resource: resource,
	})
	requireNoError(t, err)

	if token.Value != "minted" || token.Resource != "alcohol-zinc" {
		t.Fatalf("expected the grant to be mapped, got %+v", token)
	}
	// The provider reports a relative lifetime; the adapter turns it into an
	// absolute instant off the injected clock so caching is testable.
	if !token.ExpiresAt.Equal(testhelper.FixedNow().Add(10 * time.Minute)) {
		t.Fatalf("expected an absolute expiry, got %s", token.ExpiresAt)
	}
	if len(token.Scopes) != 2 {
		t.Fatalf("expected the granted scopes to win over the requested ones, got %v", token.Scopes)
	}

	sent := stub.requests[0]
	if !strings.Contains(sent.body, "grant_type=refresh_token") ||
		!strings.Contains(sent.body, "resource=https%3A%2F%2Fapi.zinc.invalid") {
		t.Fatalf("expected a per-resource refresh exchange, got %q", sent.body)
	}
	if !strings.Contains(sent.body, "scope=read%3Abooking") {
		t.Fatalf("expected the requested scopes to be sent, got %q", sent.body)
	}
	if sent.auth == "" {
		t.Fatal("expected the configured client secret to authenticate the request")
	}
}

func TestResourceTokenRefusesABlankRefreshToken(t *testing.T) {
	t.Parallel()

	client := newClient(t, newTenant(t, func(http.ResponseWriter, *http.Request) {}).config(), nil)

	_, err := client.ResourceToken(context.Background(), authengine.ResourceTokenRequest{Resource: resource})
	requireProblem(t, err, authengine.ProblemRefreshTokenUnknown)
}

func TestClientCredentialsMintsWithoutASession(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"m2m","expires_in":600}`)
	})
	client := newClient(t, stub.config(), nil)

	token, err := client.ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireNoError(t, err)

	if token.Value != "m2m" {
		t.Fatalf("expected the machine-to-machine grant, got %+v", token)
	}
	if !strings.Contains(stub.requests[0].body, "grant_type=client_credentials") {
		t.Fatalf("expected the client-credentials grant, got %q", stub.requests[0].body)
	}
	// With no granted scope the requested ones stand.
	if len(token.Scopes) != 1 || token.Scopes[0] != "read:booking" {
		t.Fatalf("expected the requested scopes to stand, got %v", token.Scopes)
	}
}

func TestAGrantWithNoLifetimeFallsBackToTheContract(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"minted"}`)
	})
	client := newClient(t, stub.config(), nil)

	token, err := client.ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: authengine.Resource{Name: "zinc"}})
	requireNoError(t, err)

	if !token.ExpiresAt.Equal(testhelper.FixedNow().Add(authengine.AccessTokenLifetime)) {
		t.Fatalf("expected the family lifetime as the fallback, got %s", token.ExpiresAt)
	}
}

func TestRefreshRotatesAndCopesWithANonRotatingProvider(t *testing.T) {
	t.Parallel()

	rotating := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"a","refresh_token":"refresh-2","expires_in":600}`)
	})
	session, err := newClient(t, rotating.config(), nil).Refresh(context.Background(), "refresh-1")
	requireNoError(t, err)
	if session.RefreshToken != "refresh-2" {
		t.Fatalf("expected the rotated token, got %q", session.RefreshToken)
	}
	if !session.RefreshExpiresAt.Equal(testhelper.FixedNow().Add(authengine.RefreshTokenLifetime)) {
		t.Fatalf("expected the family refresh window, got %s", session.RefreshExpiresAt)
	}

	// A provider that returns no replacement is not rotating; dropping the presented
	// token would end the session on the next refresh.
	static := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"a","expires_in":600}`)
	})
	session, err = newClient(t, static.config(), nil).Refresh(context.Background(), "refresh-1")
	requireNoError(t, err)
	if session.RefreshToken != "refresh-1" {
		t.Fatalf("expected the presented token to be carried forward, got %q", session.RefreshToken)
	}
}

func TestRefreshRefusesABlankToken(t *testing.T) {
	t.Parallel()

	client := newClient(t, newTenant(t, func(http.ResponseWriter, *http.Request) {}).config(), nil)

	_, err := client.Refresh(context.Background(), "")
	requireProblem(t, err, authengine.ProblemRefreshTokenUnknown)
}

func TestMintOneTimeTokenUsesTheManagementAPI(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, request *http.Request) {
		if strings.HasSuffix(request.URL.Path, "/oidc/token") {
			grant(writer, `{"access_token":"management","expires_in":600}`)
			return
		}
		grant(writer, `{"token":"one-time"}`)
	})
	client := newClient(t, stub.config(), nil)

	email := "owner@example.invalid"
	token, err := client.MintOneTimeToken(context.Background(),
		authengine.OneTimeTokenRequest{Subject: "user-1", Email: &email})
	requireNoError(t, err)

	if token.Value != "one-time" {
		t.Fatalf("expected the minted one-time token, got %+v", token)
	}
	if !token.ExpiresAt.Equal(testhelper.FixedNow().Add(authengine.OneTimeTokenLifetime)) {
		t.Fatalf("expected the 120-second contract lifetime, got %s", token.ExpiresAt)
	}

	minted := stub.requests[len(stub.requests)-1]
	if minted.method != http.MethodPost || !strings.Contains(minted.path, "one-time-tokens") {
		t.Fatalf("expected a one-time-token call, got %+v", minted)
	}
	if !strings.Contains(minted.body, `"expiresIn":120`) {
		t.Fatalf("expected the contract expiry to be requested, got %q", minted.body)
	}
	if !strings.Contains(minted.body, email) {
		t.Fatalf("expected the bound email to be sent, got %q", minted.body)
	}
	if minted.auth == "" {
		t.Fatal("expected the management call to carry a client-credentials token")
	}
}

func TestMintOneTimeTokenRefusesAnUnknownSubject(t *testing.T) {
	t.Parallel()

	client := newClient(t, newTenant(t, func(http.ResponseWriter, *http.Request) {}).config(), nil)

	_, err := client.MintOneTimeToken(context.Background(), authengine.OneTimeTokenRequest{})
	requireProblem(t, err, authengine.ProblemTokenClaimMissing)
}

func TestMintOneTimeTokenRejectsAnEmptyResponse(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, request *http.Request) {
		if strings.HasSuffix(request.URL.Path, "/oidc/token") {
			grant(writer, `{"access_token":"management","expires_in":600}`)
			return
		}
		grant(writer, `{}`)
	})

	_, err := newClient(t, stub.config(), nil).MintOneTimeToken(context.Background(),
		authengine.OneTimeTokenRequest{Subject: "user-1"})
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestSetClaimPatchesCustomData(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, request *http.Request) {
		if strings.HasSuffix(request.URL.Path, "/oidc/token") {
			grant(writer, `{"access_token":"management","expires_in":600}`)
			return
		}
		writer.WriteHeader(http.StatusNoContent)
	})
	client := newClient(t, stub.config(), nil)

	requireNoError(t, client.SetClaim(context.Background(), "user-1", "alcohol_zinc", "true"))

	patch := stub.requests[len(stub.requests)-1]
	if patch.method != http.MethodPatch || !strings.Contains(patch.path, "/api/users/user-1/custom-data") {
		t.Fatalf("expected a custom-data patch, got %+v", patch)
	}
	if !strings.Contains(patch.body, `"alcohol_zinc":"true"`) {
		t.Fatalf("expected the claim in the patch body, got %q", patch.body)
	}
}

func TestSetClaimRefusesAnIncompleteWriteBack(t *testing.T) {
	t.Parallel()

	client := newClient(t, newTenant(t, func(http.ResponseWriter, *http.Request) {}).config(), nil)
	ctx := context.Background()

	requireProblem(t, client.SetClaim(ctx, "", "alcohol_zinc", "true"), authengine.ProblemTokenClaimMissing)
	requireProblem(t, client.SetClaim(ctx, "user-1", "", "true"), authengine.ProblemTokenClaimMissing)
}

func TestSetClaimRequiresAManagementEndpoint(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(http.ResponseWriter, *http.Request) {})
	config := stub.config()
	config.IDP.Management.Endpoint = ""

	requireProblem(t,
		newClient(t, config, nil).SetClaim(context.Background(), "user-1", "c", "true"),
		authengine.ProblemConfigInvalid)
}

func TestSetClaimRejectsAnUnencodableValue(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(http.ResponseWriter, *http.Request) {})

	// A value the wire cannot carry must be reported, not silently dropped.
	requireProblem(t,
		newClient(t, stub.config(), nil).SetClaim(context.Background(), "user-1", "c", make(chan int)),
		authengine.ProblemProviderUnavailable)
}

func TestSetClaimSurfacesAFailedManagementTokenMint(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		writer.WriteHeader(http.StatusUnauthorized)
	})

	requireProblem(t,
		newClient(t, stub.config(), nil).SetClaim(context.Background(), "user-1", "c", "true"),
		authengine.ProblemTokenSignatureInvalid)
}

func TestProviderStatusesMapOntoTheEngineVocabulary(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		status int
		want   string
	}{
		{name: "unauthorized", status: http.StatusUnauthorized, want: authengine.ProblemTokenSignatureInvalid},
		{name: "forbidden", status: http.StatusForbidden, want: authengine.ProblemOwnershipDenied},
		{name: "server error", status: http.StatusInternalServerError, want: authengine.ProblemProviderUnavailable},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
				writer.WriteHeader(testCase.status)
				_, _ = io.WriteString(writer, `{"error":"nope"}`)
			})

			_, err := newClient(t, stub.config(), nil).ClientCredentials(context.Background(),
				authengine.ClientCredentialsRequest{Resource: resource})
			requireProblem(t, err, testCase.want)
		})
	}
}

func TestAGrantWithNoAccessTokenIsRejected(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"expires_in":600}`)
	})

	_, err := newClient(t, stub.config(), nil).ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestAnUndecodableResponseIsRejected(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `not json`)
	})

	_, err := newClient(t, stub.config(), nil).ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

// failingTransport reports a transport error without reaching a server.
type failingTransport struct{}

func (failingTransport) Do(*http.Request) (*http.Response, error) {
	return nil, errFake
}

func TestAnUnreachableProviderIsReported(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(http.ResponseWriter, *http.Request) {})

	_, err := newClient(t, stub.config(), failingTransport{}).ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

// brokenBody answers with a body that fails halfway through being read.
type brokenBody struct{}

func (brokenBody) Read([]byte) (int, error) { return 0, errFake }

func (brokenBody) Close() error { return nil }

// truncatingTransport answers with an unreadable body.
type truncatingTransport struct{}

func (truncatingTransport) Do(request *http.Request) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       brokenBody{},
		Request:    request,
	}, nil
}

func TestAnUnreadableResponseIsReported(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(http.ResponseWriter, *http.Request) {})

	_, err := newClient(t, stub.config(), truncatingTransport{}).ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestAnUnusableEndpointIsReportedAsConfiguration(t *testing.T) {
	t.Parallel()

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})

	client, err := logto.NewClient(logto.ClientOptions{
		Config: authengine.Config{Minting: authengine.MintingConfig{ //nolint:gosec // an endpoint URL, not a credential
			TokenEndpoint: "https://idp.invalid/\x7f",
		}},
		Problems: problems,
		Clock:    clock,
	})
	requireNoError(t, err)

	_, err = client.ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireProblem(t, err, authengine.ProblemConfigInvalid)
}

func TestAnUnusableManagementEndpointIsReportedAsConfiguration(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"management","expires_in":600}`)
	})
	config := stub.config()
	config.IDP.Management.Endpoint = "https://idp.invalid/\x7f"

	requireProblem(t,
		newClient(t, config, nil).SetClaim(context.Background(), "user-1", "c", "true"),
		authengine.ProblemConfigInvalid)
}

func TestAClockFailureIsReported(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"minted","expires_in":600}`)
	})
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})

	client, err := logto.NewClient(logto.ClientOptions{
		Config: stub.config(), Problems: problems, Clock: clock,
	})
	requireNoError(t, err)

	clock.EnqueueClockResult(time.Time{}, errFake)
	_, err = client.ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireProblem(t, err, authengine.ProblemProviderUnavailable)

	// The one-time-token path reads the clock before it calls out at all.
	clock.EnqueueClockResult(time.Time{}, errFake)
	_, err = client.MintOneTimeToken(context.Background(),
		authengine.OneTimeTokenRequest{Subject: "user-1"})
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestTheAdapterSatisfiesTheProviderSeam(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(http.ResponseWriter, *http.Request) {})

	// Assigning through the seam is the assertion: the engine only ever depends on
	// the interface, never on this adapter.
	var provider authengine.Provider = newClient(t, stub.config(), nil)
	if _, err := provider.Refresh(context.Background(), ""); err == nil {
		t.Fatal("expected the seam to reach the adapter implementation")
	}
}

func TestAResourceWithNoScopesSendsNoScopeParameter(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"minted","expires_in":600}`)
	})
	client := newClient(t, stub.config(), nil)
	bare := authengine.Resource{Name: "zinc", Indicator: "https://api.zinc.invalid"}

	_, err := client.ResourceToken(context.Background(), authengine.ResourceTokenRequest{
		Subject: "user-1", RefreshToken: "refresh-1", Resource: bare,
	})
	requireNoError(t, err)
	if strings.Contains(stub.requests[0].body, "scope=") {
		t.Fatalf("expected no scope parameter for a scopeless resource, got %q", stub.requests[0].body)
	}

	_, err = client.ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: bare})
	requireNoError(t, err)
	if strings.Contains(stub.requests[1].body, "scope=") {
		t.Fatalf("expected no scope parameter for a scopeless resource, got %q", stub.requests[1].body)
	}
}

func TestAnUnauthenticatedTokenEndpointSkipsBasicAuth(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"minted","expires_in":600}`)
	})
	config := stub.config()
	// A public client has no secret to present; sending an empty one would be worse
	// than sending none.
	config.Minting.ClientSecret = ""

	_, err := newClient(t, config, nil).ClientCredentials(context.Background(),
		authengine.ClientCredentialsRequest{Resource: resource})
	requireNoError(t, err)

	if stub.requests[0].auth != "" {
		t.Fatalf("expected no Authorization header, got %q", stub.requests[0].auth)
	}
}

func TestMintOneTimeTokenWithoutABoundEmail(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, request *http.Request) {
		if strings.HasSuffix(request.URL.Path, "/oidc/token") {
			grant(writer, `{"access_token":"management","expires_in":600}`)
			return
		}
		grant(writer, `{"token":"one-time"}`)
	})

	token, err := newClient(t, stub.config(), nil).MintOneTimeToken(context.Background(),
		authengine.OneTimeTokenRequest{Subject: "user-1"})
	requireNoError(t, err)
	if token.Value != "one-time" {
		t.Fatalf("expected the minted token, got %+v", token)
	}
	if strings.Contains(stub.requests[len(stub.requests)-1].body, "email") {
		t.Fatal("expected no email field when none was bound")
	}
}

func TestRefreshSurfacesAClockFailureAfterTheGrant(t *testing.T) {
	t.Parallel()

	stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
		grant(writer, `{"access_token":"a","refresh_token":"refresh-2","expires_in":600}`)
	})
	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal())
	requireNoError(t, err)
	clock := mocks.NewInMemorySystem(mocks.InMemorySystemOptions{Now: testhelper.FixedNow()})
	client, err := logto.NewClient(logto.ClientOptions{
		Config: stub.config(), Problems: problems, Clock: clock,
	})
	requireNoError(t, err)

	clock.EnqueueClockResult(time.Time{}, errFake)
	_, err = client.Refresh(context.Background(), "refresh-1")
	requireProblem(t, err, authengine.ProblemProviderUnavailable)
}

func TestEveryGrantPathSurfacesAProviderRejection(t *testing.T) {
	t.Parallel()

	ctx := context.Background()

	t.Run("resource token", func(t *testing.T) {
		t.Parallel()

		stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
			writer.WriteHeader(http.StatusUnauthorized)
		})
		_, err := newClient(t, stub.config(), nil).ResourceToken(ctx, authengine.ResourceTokenRequest{
			Subject: "user-1", RefreshToken: "refresh-1", Resource: resource,
		})
		requireProblem(t, err, authengine.ProblemTokenSignatureInvalid)
	})

	t.Run("refresh", func(t *testing.T) {
		t.Parallel()

		stub := newTenant(t, func(writer http.ResponseWriter, _ *http.Request) {
			writer.WriteHeader(http.StatusUnauthorized)
		})
		_, err := newClient(t, stub.config(), nil).Refresh(ctx, "refresh-1")
		requireProblem(t, err, authengine.ProblemTokenSignatureInvalid)
	})

	t.Run("one-time token", func(t *testing.T) {
		t.Parallel()

		stub := newTenant(t, func(writer http.ResponseWriter, request *http.Request) {
			if strings.HasSuffix(request.URL.Path, "/oidc/token") {
				grant(writer, `{"access_token":"management","expires_in":600}`)
				return
			}
			writer.WriteHeader(http.StatusInternalServerError)
		})
		_, err := newClient(t, stub.config(), nil).MintOneTimeToken(ctx,
			authengine.OneTimeTokenRequest{Subject: "user-1"})
		requireProblem(t, err, authengine.ProblemProviderUnavailable)
	})
}
