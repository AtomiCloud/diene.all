package apiengine_test

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
)

// The multi-backend contract: ONE consumer, MANY backends, each reached at its
// own origin with its OWN token resolved through the auth-engine seam.
func TestMultiBackendTreeResolvesTokensPerBackend(t *testing.T) {
	t.Parallel()

	route := map[string]testhelper.Route{
		"/whoami": {Status: http.StatusOK, Body: map[string]any{"ok": true}},
	}
	alpha := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Routes: route})
	beta := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Routes: route})
	gamma := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Routes: route})

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{
			"alpha": alpha, "beta": beta, "gamma": gamma,
		},
		Tokens: map[string]string{
			"alpha": "token-alpha", "beta": "token-beta", "gamma": "token-gamma",
		},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	defer tree.Close()

	if got := tree.Tree.Names(); !slices.Equal(got, []string{"alpha", "beta", "gamma"}) {
		t.Errorf("Names() = %v, want the registered backends in sorted order", got)
	}

	ctx := context.Background()
	for _, name := range tree.Tree.Names() {
		client, err := tree.Tree.Backend(name)
		if err != nil {
			t.Fatalf("resolve %s: %v", name, err)
		}
		if _, err := apiengine.Execute[map[string]any](ctx, client,
			apiengine.Request{Path: "/whoami"}); err != nil {
			t.Fatalf("call %s: %v", name, err)
		}
	}

	// Each backend must have seen ITS OWN bearer, never a sibling's.
	for name, backend := range tree.Backends {
		requests := backend.Requests()
		if len(requests) != 1 {
			t.Fatalf("%s received %d requests, want 1", name, len(requests))
		}
		want := "Bearer token-" + name
		if got := requests[0].Authorization(); got != want {
			t.Errorf("%s Authorization = %q, want %q", name, got, want)
		}
	}

	asked := tree.Retriever.Asked()
	slices.Sort(asked)
	if !slices.Equal(asked, []string{"alpha", "beta", "gamma"}) {
		t.Errorf("resources asked for = %v, want one per backend", asked)
	}
}

// A backend may override the resource name its tokens are minted under, for
// when the logical client name and the service-tree identity differ.
func TestBackendResourceOverride(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/x": {Status: http.StatusOK, Body: map[string]any{"ok": true}},
		},
	})
	defer backend.Close()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}
	retriever := testhelper.NewFakeRetriever(map[string]string{"alcohol-zinc": "token-zinc"})

	config := apiengine.DefaultConfig()
	config.Backends["zinc"] = apiengine.BackendConfig{
		BaseURL:  backend.URL(),
		Resource: "alcohol-zinc",
	}

	tree, err := apiengine.NewClientTree(apiengine.TreeOptions{
		Config:   config,
		Tokens:   retriever,
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewClientTree: %v", err)
	}
	client, err := tree.Backend("zinc")
	if err != nil {
		t.Fatalf("resolve zinc: %v", err)
	}

	if _, err := apiengine.Execute[map[string]any](context.Background(), client,
		apiengine.Request{Path: "/x"}); err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if got := retriever.Asked(); !slices.Equal(got, []string{"alcohol-zinc"}) {
		t.Errorf("resources asked for = %v, want the overridden resource name", got)
	}
	if got := backend.Requests()[0].Authorization(); got != "Bearer token-zinc" {
		t.Errorf("Authorization = %q, want the overridden resource's token", got)
	}
}

// A backend with no retriever is called unauthenticated: not every backend
// needs credentials.
func TestBackendWithoutCredentialsSendsNoAuthorization(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/open": {Status: http.StatusOK, Body: map[string]any{"ok": true}},
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"open": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	client, err := tree.Tree.Backend("open")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}

	if _, err := apiengine.Execute[map[string]any](context.Background(), client,
		apiengine.Request{Path: "/open"}); err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if got := backend.Requests()[0].Authorization(); got != "" {
		t.Errorf("Authorization = %q, want none", got)
	}
}

// A token that will not resolve stops the request before it is sent: sending an
// unauthenticated call to a backend that needs credentials would just produce a
// confusing 401.
func TestUnresolvableCredentialsStopTheRequest(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/x": {Status: http.StatusOK, Body: map[string]any{"ok": true}},
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"api": backend},
		Tokens:   map[string]string{"api": "token"},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	tree.Retriever.FailResource("api", errors.New("the IdP is down"))

	client, err := tree.Tree.Backend("api")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}
	_, err = apiengine.Execute[map[string]any](context.Background(), client,
		apiengine.Request{Path: "/x"})
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend credentials unavailable",
		Status: http.StatusBadGateway,
	})
	if envelope.Data["resource"] != "api" {
		t.Errorf("data.resource = %v, want api", envelope.Data["resource"])
	}
	testhelper.AssertCount(t, backend, 0)
}

func TestUnregisteredBackendIsReported(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"known": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}

	client, err := tree.Tree.Backend("unknown")
	if client != nil {
		t.Error("Backend(unknown): want a nil client")
	}
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend not registered",
		Status: http.StatusInternalServerError,
	})
	if envelope.Data["backend"] != "unknown" {
		t.Errorf("data.backend = %v, want unknown", envelope.Data["backend"])
	}
}

func TestNewClientTreeValidatesAndDefaults(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	if _, missing := apiengine.NewClientTree(apiengine.TreeOptions{}); missing == nil {
		t.Error("NewClientTree without problems: want an error, got none")
	}

	bad := apiengine.DefaultConfig()
	bad.Backends["broken"] = apiengine.BackendConfig{BaseURL: "not-a-url"}
	_, err = apiengine.NewClientTree(apiengine.TreeOptions{Config: bad, Problems: problems})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{Title: "Api configuration invalid"})

	// With no doer the tree falls back to http.DefaultClient rather than
	// refusing to build.
	empty, err := apiengine.NewClientTree(apiengine.TreeOptions{
		Config: apiengine.DefaultConfig(), Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewClientTree: %v", err)
	}
	if got := empty.Names(); len(got) != 0 {
		t.Errorf("Names() = %v, want none", got)
	}
	if empty.Problems() != problems {
		t.Error("Problems(): want the factory the tree was built with")
	}
	// An empty tree still reports an unregistered backend rather than panicking.
	if _, err := empty.Backend("nope"); err == nil {
		t.Error("Backend on an empty tree: want an error, got none")
	}
}
