package apiengine_test

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"sync"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// badPortal carries a service segment containing a slash. The registry accepts
// it, but building a type URI from it fails — which is exactly the
// consumer-side misconfiguration the uncatalogued fallback exists for.
func badPortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme: "https", Host: "docs.example.com",
		Landscape: "prod", Platform: "api", Service: "billing/v2", Module: "core",
	}
}

// A failure to describe a failure must never replace it: an unbuildable type
// URI still has to surface the original detail.
func TestUnbuildableTypeURIDegradesToUncatalogued(t *testing.T) {
	t.Parallel()

	problems, err := apiengine.NewProblems(badPortal())
	if err != nil {
		t.Fatalf("NewProblems: %v", err)
	}

	err = problems.Raise(apiengine.ProblemTransport, "the backend vanished",
		map[string]any{"backend": "billing"})
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Detail: "the backend vanished",
		Data:   map[string]any{"backend": "billing"},
	})
	if envelope.Status != 500 {
		t.Errorf("status = %d, want the 500 uncatalogued fallback", envelope.Status)
	}
}

func TestCatalogFailsOnAnUnbuildableTypeURI(t *testing.T) {
	t.Parallel()

	problems, err := apiengine.NewProblems(badPortal())
	if err != nil {
		t.Fatalf("NewProblems: %v", err)
	}
	if _, err := problems.Catalog(); err == nil {
		t.Error("Catalog with an unbuildable portal: want an error, got none")
	}
}

// A base URL that passes the scheme check but is not a parseable origin is a
// construction failure, not a surprise on the first call.
func TestMalformedBaseURLFailsAtConstruction(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	_, err = apiengine.NewClient(apiengine.ClientOptions{
		Backend:  "api",
		Config:   apiengine.BackendConfig{BaseURL: "https://[::1"},
		Doer:     http.DefaultClient,
		Problems: problems,
	})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Api configuration invalid",
		Status: http.StatusInternalServerError,
	})

	// And the tree refuses to build rather than handing back a half-populated
	// registry.
	config := apiengine.DefaultConfig()
	config.Backends["api"] = apiengine.BackendConfig{BaseURL: "https://[::1"}
	_, err = apiengine.NewClientTree(apiengine.TreeOptions{Config: config, Problems: problems})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title: "Api configuration invalid",
	})
}

// flakyRetriever resolves a token the first time and fails afterwards, so the
// retry's rebuild can fail even though the original build succeeded.
type flakyRetriever struct {
	mu    sync.Mutex
	calls int
}

func (r *flakyRetriever) Token(_ context.Context, resource string) (authengine.AccessToken, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls++
	if r.calls > 1 {
		return authengine.AccessToken{}, errors.New("the IdP went away mid-retry")
	}
	return authengine.AccessToken{Value: "token", Resource: resource}, nil
}

// The retry rebuilds the request, because a body already consumed cannot be
// replayed — so a rebuild that fails must surface, not be swallowed.
func TestRetryRebuildFailureSurfaces(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}
	doer := &countingDoer{err: errors.New("connection reset")}

	client, err := apiengine.NewClient(apiengine.ClientOptions{
		Backend:  "api",
		Config:   apiengine.BackendConfig{BaseURL: "https://example.invalid"},
		Doer:     doer,
		Tokens:   &flakyRetriever{},
		Problems: problems,
		Retry:    apiengine.RetryConfig{Network: true},
	})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}

	_, err = client.Call(context.Background(), apiengine.Request{Path: "/x"})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend credentials unavailable",
		Status: http.StatusBadGateway,
	})
	if doer.attempts != 1 {
		t.Errorf("round trips = %d, want 1 before the rebuild failed", doer.attempts)
	}
}

// The required members are present but their shapes are wrong, so the
// envelope's own decoder — the authority on member types — rejects it.
func TestDecodeProblemRejectsMalformedMembers(t *testing.T) {
	t.Parallel()

	bodies := []string{
		`{"type":"https://x","status":"409"}`,
		`{"title":"t","status":[1]}`,
		`{"type":123,"title":"t"}`,
	}
	for _, body := range bodies {
		if _, ok := apiengine.DecodeProblem([]byte(body)); ok {
			t.Errorf("DecodeProblem(%s): want false, got true", body)
		}
	}
}

// A non-conformant 4xx whose body is not an envelope reaches the caller as the
// engine's own problem naming the backend.
func TestExecuteNamesTheNonConformantBackend(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/odd": {Status: http.StatusConflict, Body: `{"type":"https://x","status":"409"}`},
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"odd": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	client, err := tree.Tree.Backend("odd")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}

	_, err = apiengine.Execute[user](context.Background(), client, apiengine.Request{Path: "/odd"})
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend error was not a problem envelope",
		Status: http.StatusBadGateway,
	})
	if envelope.Detail == nil || !strings.Contains(*envelope.Detail, "odd") {
		t.Errorf("detail = %v, want the backend named", envelope.Detail)
	}
}
