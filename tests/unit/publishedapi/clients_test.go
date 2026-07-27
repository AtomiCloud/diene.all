package publishedapi_test

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	authtest "github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/AtomiCloud/diene.go-consumer/lib/publishedapi"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfacestest "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

const (
	identityEndpoint = "https://identity.example.test/oidc/token"
	backendOrigin    = "https://control.example.test"
)

type recordingDoer struct {
	tokenCalls          int
	backendCalls        int
	grantType           string
	resource            string
	scope               string
	clientID            string
	basicUser           string
	basicSecret         string
	basicAuthentication bool
	backendAuth         []string
}

func (fake *recordingDoer) Do(request *http.Request) (*http.Response, error) {
	switch request.URL.String() {
	case identityEndpoint:
		if err := request.ParseForm(); err != nil {
			return nil, fmt.Errorf("parse token form: %w", err)
		}
		fake.tokenCalls++
		fake.grantType = request.Form.Get("grant_type")
		fake.resource = request.Form.Get("resource")
		fake.scope = request.Form.Get("scope")
		fake.clientID = request.Form.Get("client_id")
		fake.basicUser, fake.basicSecret, fake.basicAuthentication = request.BasicAuth()
		return jsonResponse(http.StatusOK, `{"access_token":"minted-token","expires_in":3600}`), nil
	case backendOrigin + "/v1/sample":
		fake.backendCalls++
		fake.backendAuth = append(fake.backendAuth, request.Header.Get("Authorization"))
		return jsonResponse(http.StatusOK, `{"source":"control-plane"}`), nil
	default:
		return nil, fmt.Errorf("unexpected request URL %q", request.URL.String())
	}
}

func TestNewClientTreeMintsCachesAndAttachesClientCredentials(t *testing.T) {
	t.Parallel()

	store := authtest.NewMemoryTokenStore()
	system := interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{
		Now: time.Date(2026, time.July, 26, 22, 0, 0, 0, time.UTC),
	})
	doer := &recordingDoer{}
	tree, err := publishedapi.NewClientTree(
		problem.LocalErrorPortal(), validAPIConfig(), validAuthConfig(), store, system, doer,
	)
	if err != nil {
		t.Fatalf("NewClientTree() error = %v", err)
	}
	client, err := tree.Backend("control")
	if err != nil {
		t.Fatalf("Backend() error = %v", err)
	}

	type response struct {
		Source string `json:"source"`
	}
	for range 2 {
		actual, executeErr := apiengine.Execute[response](
			context.Background(), client, apiengine.Request{Path: "/v1/sample"},
		)
		if executeErr != nil {
			t.Fatalf("Execute() error = %v", executeErr)
		}
		if actual.Source != "control-plane" {
			t.Fatalf("Execute() source = %q", actual.Source)
		}
	}

	if doer.tokenCalls != 1 || doer.backendCalls != 2 {
		t.Fatalf("request counts = token %d, backend %d", doer.tokenCalls, doer.backendCalls)
	}
	if doer.grantType != "client_credentials" || doer.resource != "https://control.example.test/api" ||
		doer.scope != "sample.read sample.write" || doer.clientID != "worker-client" {
		t.Fatalf("token form = grant %q, resource %q, scope %q, client ID %q",
			doer.grantType, doer.resource, doer.scope, doer.clientID)
	}
	if !doer.basicAuthentication || doer.basicUser != "worker-client" || doer.basicSecret != "worker-secret" {
		t.Fatalf("basic authentication = present %t, user %q, secret %q",
			doer.basicAuthentication, doer.basicUser, doer.basicSecret)
	}
	if len(doer.backendAuth) != 2 || doer.backendAuth[0] != "Bearer minted-token" ||
		doer.backendAuth[1] != "Bearer minted-token" {
		t.Fatalf("backend authorization = %#v", doer.backendAuth)
	}
	if keys := store.Keys(); len(keys) != 1 || keys[0] != "go-consumer:control" {
		t.Fatalf("token-store keys = %#v", keys)
	}
}

func TestNewClientTreeReportsReachableConstructionFailures(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		change func(*apiengine.Config, *authengine.Config, *authengine.TokenStore, *interfaces.System)
	}{
		{
			name: "resource tree",
			change: func(apiConfig *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				apiConfig.Backends["archive"] = apiengine.BackendConfig{
					BaseURL: backendOrigin, Resource: "control", Indicator: "https://archive.example.test/api",
				}
			},
		},
		{
			name: "token endpoint",
			change: func(_ *apiengine.Config, authConfig *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				authConfig.Minting.TokenEndpoint = ""
			},
		},
		{
			name: "clock seam",
			change: func(_ *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, system *interfaces.System) {
				*system = nil
			},
		},
		{
			name: "token store",
			change: func(_ *apiengine.Config, _ *authengine.Config, store *authengine.TokenStore, _ *interfaces.System) {
				*store = nil
			},
		},
		{
			name: "blank backend name",
			change: func(apiConfig *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				apiConfig.Backends[""] = apiengine.BackendConfig{BaseURL: backendOrigin}
			},
		},
		{
			name: "blank backend origin",
			change: func(apiConfig *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				backend := apiConfig.Backends["control"]
				backend.BaseURL = " "
				apiConfig.Backends["control"] = backend
			},
		},
		{
			name: "relative backend origin",
			change: func(apiConfig *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				backend := apiConfig.Backends["control"]
				backend.BaseURL = "/control"
				apiConfig.Backends["control"] = backend
			},
		},
		{
			name: "negative backend timeout",
			change: func(apiConfig *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				backend := apiConfig.Backends["control"]
				backend.Timeout = wire.Duration(-time.Second)
				apiConfig.Backends["control"] = backend
			},
		},
		{
			name: "negative retry delay",
			change: func(apiConfig *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				apiConfig.Retry.Delay = wire.Duration(-time.Second)
			},
		},
		{
			name: "malformed backend origin",
			change: func(apiConfig *apiengine.Config, _ *authengine.Config, _ *authengine.TokenStore, _ *interfaces.System) {
				backend := apiConfig.Backends["control"]
				backend.BaseURL = "http://[::1"
				apiConfig.Backends["control"] = backend
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			apiConfig := validAPIConfig()
			authConfig := validAuthConfig()
			var store authengine.TokenStore = authtest.NewMemoryTokenStore()
			var system interfaces.System = interfacestest.NewInMemorySystem(interfacestest.InMemorySystemOptions{})
			test.change(&apiConfig, &authConfig, &store, &system)

			tree, err := publishedapi.NewClientTree(
				problem.LocalErrorPortal(), apiConfig, authConfig, store, system, &recordingDoer{},
			)
			if tree != nil {
				t.Fatalf("NewClientTree() tree = %#v, want nil", tree)
			}
			assertConfigProblem(t, err)
		})
	}
}

func validAPIConfig() apiengine.Config {
	config := apiengine.DefaultConfig()
	config.Backends["control"] = apiengine.BackendConfig{
		BaseURL:   backendOrigin,
		Resource:  "control",
		Indicator: "https://control.example.test/api",
		Scopes:    []string{"sample.read", "sample.write"},
		Timeout:   wire.Duration(5 * time.Second),
	}
	return config
}

func validAuthConfig() authengine.Config {
	return authengine.Config{
		Minting: authengine.MintingConfig{
			TokenEndpoint:      identityEndpoint,
			ClientID:           "worker-client",
			ClientSecret:       "worker-secret",
			CacheNamespace:     "go-consumer",
			RefreshSkewSeconds: 30,
			Concurrency:        2,
		},
	}
}

func jsonResponse(status int, body string) *http.Response {
	return &http.Response{
		StatusCode: status,
		Header:     make(http.Header),
		Body:       io.NopCloser(strings.NewReader(body)),
	}
}

func assertConfigProblem(t *testing.T, err error) {
	t.Helper()
	if err == nil {
		t.Fatal("NewClientTree() error = nil")
	}
	var carried *problem.Error
	if !errors.As(err, &carried) {
		t.Fatalf("NewClientTree() error is not problem typed: %T %v", err, err)
	}
	if !strings.HasSuffix(carried.Problem.Type, "/"+authengine.ProblemConfigInvalid) {
		t.Fatalf("NewClientTree() problem type = %q", carried.Problem.Type)
	}
}
