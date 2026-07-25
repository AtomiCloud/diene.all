package apiengine_test

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/lib/wire"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
)

// okRoutes is the single-route backend most client tests need.
func okRoutes() map[string]testhelper.Route {
	return map[string]testhelper.Route{
		"/v1/things": {Status: http.StatusOK, Body: map[string]any{"ok": true}},
	}
}

// The resilience profile is retry-once-on-network-error, and nothing else: one
// transport failure is survived, two are not, and a 5xx is never retried.
func TestRetryOnceOnNetworkError(t *testing.T) {
	t.Parallel()

	t.Run("a single transport failure is retried exactly once", func(t *testing.T) {
		t.Parallel()
		backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
			Routes:            okRoutes(),
			TransportFailures: 1,
		})
		defer backend.Close()

		tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
			Backends: map[string]*testhelper.FakeBackend{"api": backend},
			Retry:    apiengine.RetryConfig{Network: true},
		})
		if err != nil {
			t.Fatalf("build tree: %v", err)
		}
		client, err := tree.Tree.Backend("api")
		if err != nil {
			t.Fatalf("resolve backend: %v", err)
		}

		got, err := apiengine.Execute[map[string]any](context.Background(), client,
			apiengine.Request{Path: "/v1/things"})
		if err != nil {
			t.Fatalf("Execute: unexpected error %v", err)
		}
		flag, isBool := got["ok"].(bool)
		if !isBool || !flag {
			t.Errorf("Execute = %v, want the retried response", got)
		}
		testhelper.AssertCount(t, backend, 2)
	})

	t.Run("a second transport failure is not retried again", func(t *testing.T) {
		t.Parallel()
		backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
			Routes:            okRoutes(),
			TransportFailures: 2,
		})
		defer backend.Close()

		tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
			Backends: map[string]*testhelper.FakeBackend{"api": backend},
			Retry:    apiengine.RetryConfig{Network: true},
		})
		if err != nil {
			t.Fatalf("build tree: %v", err)
		}
		client, err := tree.Tree.Backend("api")
		if err != nil {
			t.Fatalf("resolve backend: %v", err)
		}

		_, err = apiengine.Execute[map[string]any](context.Background(), client,
			apiengine.Request{Path: "/v1/things"})
		testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
			Title:  "Backend transport failed",
			Status: http.StatusBadGateway,
		})
		// Exactly two attempts: the original and the one permitted retry. A
		// third would be a stampede.
		testhelper.AssertCount(t, backend, 2)
	})

	t.Run("the retry is skipped when the profile disables it", func(t *testing.T) {
		t.Parallel()
		backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
			Routes:            okRoutes(),
			TransportFailures: 1,
		})
		defer backend.Close()

		tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
			Backends: map[string]*testhelper.FakeBackend{"api": backend},
			Retry:    apiengine.RetryConfig{Network: false},
		})
		if err != nil {
			t.Fatalf("build tree: %v", err)
		}
		client, err := tree.Tree.Backend("api")
		if err != nil {
			t.Fatalf("resolve backend: %v", err)
		}

		_, err = apiengine.Execute[map[string]any](context.Background(), client,
			apiengine.Request{Path: "/v1/things"})
		if err == nil {
			t.Fatal("Execute: want a transport error, got none")
		}
		testhelper.AssertCount(t, backend, 1)
	})

	t.Run("a 5xx is not a network error and is never retried", func(t *testing.T) {
		t.Parallel()
		backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
			Routes: map[string]testhelper.Route{
				"/v1/things": {Status: http.StatusServiceUnavailable, Body: `{"down":true}`},
			},
		})
		defer backend.Close()

		tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
			Backends: map[string]*testhelper.FakeBackend{"api": backend},
			Retry:    apiengine.RetryConfig{Network: true},
		})
		if err != nil {
			t.Fatalf("build tree: %v", err)
		}
		client, err := tree.Tree.Backend("api")
		if err != nil {
			t.Fatalf("resolve backend: %v", err)
		}

		_, err = apiengine.Execute[map[string]any](context.Background(), client,
			apiengine.Request{Path: "/v1/things"})
		if err == nil {
			t.Fatal("Execute: want a transport error, got none")
		}
		testhelper.AssertCount(t, backend, 1)
	})
}

// The configured retry delay is honoured through the injected sleep seam, so a
// consumer can prove the pause happens without waiting for it.
func TestRetryDelayIsApplied(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes:            okRoutes(),
		TransportFailures: 1,
	})
	defer backend.Close()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	var slept []time.Duration
	client, err := apiengine.NewClient(apiengine.ClientOptions{
		Backend:  "api",
		Config:   apiengine.BackendConfig{BaseURL: backend.URL()},
		Doer:     http.DefaultClient,
		Problems: problems,
		Retry: apiengine.RetryConfig{
			Network: true,
			Delay:   wire.Duration(200 * time.Millisecond),
		},
		Sleep: func(d time.Duration) { slept = append(slept, d) },
	})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}

	if _, err := apiengine.Execute[map[string]any](context.Background(), client,
		apiengine.Request{Path: "/v1/things"}); err != nil {
		t.Fatalf("Execute: unexpected error %v", err)
	}
	if len(slept) != 1 || slept[0] != 200*time.Millisecond {
		t.Errorf("sleeps = %v, want exactly one 200ms pause", slept)
	}
}

func TestRequestBuilding(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/v1/things": {Status: http.StatusOK, Body: map[string]any{"ok": true}},
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"api": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	client, err := tree.Tree.Backend("api")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}

	header := http.Header{}
	header.Set("X-Trace", "abc")
	if _, err := apiengine.Execute[map[string]any](context.Background(), client, apiengine.Request{
		Method: http.MethodPost,
		Path:   "v1/things", // no leading slash: the engine adds one
		Query:  url.Values{"page": []string{"2"}, "size": []string{"50"}},
		Header: header,
		Body:   map[string]any{"name": "Ada"},
	}); err != nil {
		t.Fatalf("Execute: unexpected error %v", err)
	}

	requests := backend.Requests()
	if len(requests) != 1 {
		t.Fatalf("requests = %d, want 1", len(requests))
	}
	got := requests[0]
	if got.Method != http.MethodPost {
		t.Errorf("method = %q, want POST", got.Method)
	}
	if got.Path != "/v1/things" {
		t.Errorf("path = %q, want /v1/things", got.Path)
	}
	if got.Query != "page=2&size=50" {
		t.Errorf("query = %q, want page=2&size=50", got.Query)
	}
	if got.Header.Get("X-Trace") != "abc" {
		t.Errorf("X-Trace = %q, want abc", got.Header.Get("X-Trace"))
	}
	if got.Header.Get("Content-Type") != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", got.Header.Get("Content-Type"))
	}
	if got.Header.Get("Accept") != "application/json, application/problem+json" {
		t.Errorf("Accept = %q, want the JSON+problem accept", got.Header.Get("Accept"))
	}
	if string(got.Body) != `{"name":"Ada"}` {
		t.Errorf("body = %s, want the encoded request body", got.Body)
	}
}

func TestRequestBuildingFailures(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	t.Run("a body that will not encode", func(t *testing.T) {
		t.Parallel()
		client, err := apiengine.NewClient(apiengine.ClientOptions{
			Backend:  "api",
			Config:   apiengine.BackendConfig{BaseURL: "https://example.invalid"},
			Doer:     http.DefaultClient,
			Problems: problems,
		})
		if err != nil {
			t.Fatalf("NewClient: %v", err)
		}
		_, err = apiengine.Execute[map[string]any](context.Background(), client,
			apiengine.Request{Body: make(chan int)})
		testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
			Title:  "Request could not be built",
			Status: http.StatusInternalServerError,
		})
	})

	t.Run("a path that will not parse", func(t *testing.T) {
		t.Parallel()
		client, err := apiengine.NewClient(apiengine.ClientOptions{
			Backend:  "api",
			Config:   apiengine.BackendConfig{BaseURL: "https://example.invalid"},
			Doer:     http.DefaultClient,
			Problems: problems,
		})
		if err != nil {
			t.Fatalf("NewClient: %v", err)
		}
		_, err = apiengine.Execute[map[string]any](context.Background(), client,
			apiengine.Request{Path: "/\x7f\x00"})
		testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
			Title:  "Request could not be built",
			Status: http.StatusInternalServerError,
		})
	})

	t.Run("a method that is not a token", func(t *testing.T) {
		t.Parallel()
		client, err := apiengine.NewClient(apiengine.ClientOptions{
			Backend:  "api",
			Config:   apiengine.BackendConfig{BaseURL: "https://example.invalid"},
			Doer:     http.DefaultClient,
			Problems: problems,
		})
		if err != nil {
			t.Fatalf("NewClient: %v", err)
		}
		_, err = apiengine.Execute[map[string]any](context.Background(), client,
			apiengine.Request{Method: "BAD METHOD"})
		testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
			Title:  "Request could not be built",
			Status: http.StatusInternalServerError,
		})
	})
}

func TestNewClientRejectsIncompleteOptions(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	if _, missing := apiengine.NewClient(apiengine.ClientOptions{Backend: "api"}); missing == nil {
		t.Error("NewClient without problems: want an error, got none")
	}
	_, err = apiengine.NewClient(apiengine.ClientOptions{Backend: "api", Problems: problems})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{Title: "Api configuration invalid"})

	_, err = apiengine.NewClient(apiengine.ClientOptions{
		Backend: "api", Problems: problems, Doer: http.DefaultClient,
	})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{Title: "Api configuration invalid"})
}

func TestClientAccessors(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}
	client, err := apiengine.NewClient(apiengine.ClientOptions{
		Backend:  "api",
		Config:   apiengine.BackendConfig{BaseURL: "https://example.invalid/"},
		Doer:     http.DefaultClient,
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}

	if client.Backend() != "api" {
		t.Errorf("Backend() = %q, want api", client.Backend())
	}
	// The trailing slash is removed so joining a path never doubles it.
	if client.BaseURL() != "https://example.invalid" {
		t.Errorf("BaseURL() = %q, want the origin without a trailing slash", client.BaseURL())
	}
}

// A response whose body dies mid-read is distinct from one that never arrived.
func TestUnreadableResponseIsReported(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}
	client, err := apiengine.NewClient(apiengine.ClientOptions{
		Backend:  "api",
		Config:   apiengine.BackendConfig{BaseURL: "https://example.invalid"},
		Doer:     brokenBodyDoer{},
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}

	_, err = client.Call(context.Background(), apiengine.Request{Path: "/x"})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend response unreadable",
		Status: http.StatusBadGateway,
	})
}

// Call surfaces a non-success status as a classified response rather than an
// error, so a caller that wants the status can have it.
func TestCallReturnsClassifiedResponse(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/gone": testhelper.Canned(testhelper.ProblemOptions{
				Type: "https://x/gone", Title: "Gone", Status: http.StatusGone,
			}),
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"api": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	client, err := tree.Tree.Backend("api")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}

	response, err := client.Call(context.Background(), apiengine.Request{Path: "/gone"})
	if err != nil {
		t.Fatalf("Call: unexpected error %v", err)
	}
	testhelper.AssertOutcome(t, response.Outcome, apiengine.OutcomeProblem)
	if response.Status != http.StatusGone {
		t.Errorf("status = %d, want 410", response.Status)
	}
	if response.Header.Get("Content-Type") != "application/problem+json" {
		t.Errorf("Content-Type = %q, want application/problem+json",
			response.Header.Get("Content-Type"))
	}
	if len(response.Body) == 0 {
		t.Error("body: want the envelope, got nothing")
	}
}

// The unregistered-route fallback answers with an RFC 9457 envelope, because a
// real C0-conformant backend does not answer a miss with a bare status.
func TestFakeBackendFallbackIsAProblemEnvelope(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"api": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	client, err := tree.Tree.Backend("api")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}

	_, err = apiengine.Execute[map[string]any](context.Background(), client,
		apiengine.Request{Path: "/nothing-here"})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Entity not found",
		Status: http.StatusNotFound,
	})
}

// The request timeout comes from the backend's own config block.
func TestPerBackendTimeoutIsHonoured(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}
	client, err := apiengine.NewClient(apiengine.ClientOptions{
		Backend: "slow",
		Config: apiengine.BackendConfig{
			BaseURL: "https://example.invalid",
			Timeout: wire.Duration(time.Millisecond),
		},
		Doer:     slowDoer{},
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}

	_, err = client.Call(context.Background(), apiengine.Request{Path: "/x"})
	if err == nil {
		t.Fatal("Call: want a timeout error, got none")
	}
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend transport failed",
		Status: http.StatusBadGateway,
	})
}

// A doer whose error is already problem-typed keeps that envelope rather than
// being wrapped a second time.
func TestProblemTypedTransportErrorIsNotReWrapped(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}
	inner := problems.Raise(apiengine.ProblemCredentialsUnavailable, "no token", nil)

	client, err := apiengine.NewClient(apiengine.ClientOptions{
		Backend:  "api",
		Config:   apiengine.BackendConfig{BaseURL: "https://example.invalid"},
		Doer:     failingDoer{err: inner},
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}

	_, err = client.Call(context.Background(), apiengine.Request{Path: "/x"})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend credentials unavailable",
		Status: http.StatusBadGateway,
	})
	if !errors.Is(err, inner) {
		t.Error("want the original problem-typed error preserved")
	}
}
