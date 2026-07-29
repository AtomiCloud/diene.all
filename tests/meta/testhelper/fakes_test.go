package testhelper_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"slices"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// fetched is the part of a response these tests assert on. The helper returns
// this rather than an *http.Response so the body is provably closed here, in one
// place, instead of at every call site.
type fetched struct {
	StatusCode int
	Header     http.Header
}

// get performs a plain GET against a fake backend without going through the
// engine, so the fake is proven on its own terms rather than through the code
// it is meant to test.
func get(t *testing.T, url string) (fetched, []byte) {
	t.Helper()
	//nolint:noctx,gosec // a fixture call against an in-process test server
	response, err := http.Get(url)
	if err != nil {
		t.Fatalf("GET %s: %v", url, err)
	}
	defer func() { _ = response.Body.Close() }()

	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatalf("read body of %s: %v", url, err)
	}
	return fetched{StatusCode: response.StatusCode, Header: response.Header}, body
}

func TestFakeBackendServesRoutesAndDefaults(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/json":    {Status: http.StatusOK, Body: map[string]any{"ok": true}},
			"/string":  {Status: http.StatusOK, Body: `{"raw":true}`},
			"/bytes":   {Status: http.StatusOK, Body: []byte(`{"bytes":true}`)},
			"/empty":   {Status: http.StatusNoContent},
			"/default": {Body: "defaulted"},
		},
	})
	defer backend.Close()

	if !strings.HasPrefix(backend.URL(), "http://") {
		t.Errorf("URL() = %q, want an http origin", backend.URL())
	}

	t.Run("a struct body is JSON-encoded and typed", func(t *testing.T) {
		response, body := get(t, backend.URL()+"/json")
		if response.StatusCode != http.StatusOK {
			t.Errorf("status = %d, want 200", response.StatusCode)
		}
		if response.Header.Get("Content-Type") != "application/json" {
			t.Errorf("Content-Type = %q, want application/json", response.Header.Get("Content-Type"))
		}
		var decoded map[string]any
		if err := json.Unmarshal(body, &decoded); err != nil {
			t.Fatalf("decode: %v", err)
		}
		flag, isBool := decoded["ok"].(bool)
		if !isBool || !flag {
			t.Errorf("body = %s, want the encoded struct", body)
		}
	})

	t.Run("a string body is served verbatim", func(t *testing.T) {
		_, body := get(t, backend.URL()+"/string")
		if string(body) != `{"raw":true}` {
			t.Errorf("body = %s, want the string verbatim", body)
		}
	})

	t.Run("a byte body is served verbatim", func(t *testing.T) {
		_, body := get(t, backend.URL()+"/bytes")
		if string(body) != `{"bytes":true}` {
			t.Errorf("body = %s, want the bytes verbatim", body)
		}
	})

	t.Run("a nil body sends nothing", func(t *testing.T) {
		response, body := get(t, backend.URL()+"/empty")
		if response.StatusCode != http.StatusNoContent {
			t.Errorf("status = %d, want 204", response.StatusCode)
		}
		if len(body) != 0 {
			t.Errorf("body = %s, want nothing", body)
		}
	})

	t.Run("an unset status defaults to 200", func(t *testing.T) {
		response, _ := get(t, backend.URL()+"/default")
		if response.StatusCode != http.StatusOK {
			t.Errorf("status = %d, want the 200 default", response.StatusCode)
		}
	})
}

// The default fallback is an RFC 9457 envelope, because a real C0-conformant
// backend does not answer a miss with a bare status.
func TestFakeBackendFallbacks(t *testing.T) {
	t.Parallel()

	t.Run("the default fallback is a problem envelope", func(t *testing.T) {
		t.Parallel()
		backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
		defer backend.Close()

		response, body := get(t, backend.URL()+"/missing")
		if response.StatusCode != http.StatusNotFound {
			t.Errorf("status = %d, want 404", response.StatusCode)
		}
		decoded, ok := apiengine.DecodeProblem(body)
		if !ok {
			t.Fatalf("fallback body %s is not a problem envelope", body)
		}
		if decoded.Title != "Entity not found" {
			t.Errorf("title = %q, want Entity not found", decoded.Title)
		}
	})

	t.Run("an overridden fallback is used", func(t *testing.T) {
		t.Parallel()
		backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
			Fallback: &testhelper.Route{Status: http.StatusTeapot, Body: "brewing"},
		})
		defer backend.Close()

		response, body := get(t, backend.URL()+"/missing")
		if response.StatusCode != http.StatusTeapot {
			t.Errorf("status = %d, want 418", response.StatusCode)
		}
		if string(body) != "brewing" {
			t.Errorf("body = %s, want the overridden fallback", body)
		}
	})
}

func TestFakeBackendRecordsRequests(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{"/x": {Status: http.StatusOK, Body: "ok"}},
	})
	defer backend.Close()

	if backend.Count() != 0 {
		t.Errorf("Count() = %d on a fresh backend, want 0", backend.Count())
	}

	request, err := http.NewRequestWithContext(context.Background(),
		http.MethodPost, backend.URL()+"/x?page=2", strings.NewReader(`{"in":1}`))
	if err != nil {
		t.Fatalf("build request: %v", err)
	}
	request.Header.Set("Authorization", "Bearer token-x")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	_ = response.Body.Close()

	recorded := backend.Requests()
	if len(recorded) != 1 {
		t.Fatalf("Requests() = %d, want 1", len(recorded))
	}
	got := recorded[0]
	if got.Method != http.MethodPost {
		t.Errorf("method = %q, want POST", got.Method)
	}
	if got.Path != "/x" {
		t.Errorf("path = %q, want /x", got.Path)
	}
	if got.Query != "page=2" {
		t.Errorf("query = %q, want page=2", got.Query)
	}
	if got.Authorization() != "Bearer token-x" {
		t.Errorf("Authorization() = %q, want the sent bearer", got.Authorization())
	}
	if string(got.Body) != `{"in":1}` {
		t.Errorf("body = %s, want the sent body", got.Body)
	}
	if backend.Count() != 1 {
		t.Errorf("Count() = %d, want 1", backend.Count())
	}

	// The returned slice is a copy: a caller cannot corrupt the fake's log.
	recorded[0].Path = "/mutated"
	if backend.Requests()[0].Path != "/x" {
		t.Error("Requests() must return a copy, not the fake's own slice")
	}
}

func TestFakeBackendSetRoute(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
	defer backend.Close()

	backend.SetRoute("/late", testhelper.Route{Status: http.StatusOK, Body: "late"})
	_, body := get(t, backend.URL()+"/late")
	if string(body) != "late" {
		t.Errorf("body = %s, want the route added after start", body)
	}

	backend.SetRoute("/late", testhelper.Route{Status: http.StatusOK, Body: "replaced"})
	_, body = get(t, backend.URL()+"/late")
	if string(body) != "replaced" {
		t.Errorf("body = %s, want the replaced route", body)
	}
}

// A fixture that will not encode is a test-authoring mistake; it must surface
// rather than panic inside a server goroutine where the stack means nothing.
func TestFakeBackendReportsAnUnencodableFixture(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{"/bad": {Status: http.StatusOK, Body: make(chan int)}},
	})
	defer backend.Close()

	_, body := get(t, backend.URL()+"/bad")
	if !strings.Contains(string(body), "did not encode") {
		t.Errorf("body = %s, want the encoding failure reported", body)
	}
}

func TestFakeBackendTransportFailures(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes:            map[string]testhelper.Route{"/x": {Status: http.StatusOK, Body: "ok"}},
		TransportFailures: 1,
	})
	defer backend.Close()

	// The first round trip dies mid-request; the fake still records it.
	if _, err := http.Get(backend.URL() + "/x"); err == nil { //nolint:bodyclose,noctx,gosec // the connection is dropped
		t.Error("want the first request to fail at the transport")
	}
	if backend.Count() != 1 {
		t.Errorf("Count() = %d, want the failed attempt recorded", backend.Count())
	}

	// The failure budget is spent, so the next one succeeds.
	_, body := get(t, backend.URL()+"/x")
	if string(body) != "ok" {
		t.Errorf("body = %s, want the served route once failures are spent", body)
	}
}

func TestFakeBackendConfigEntry(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
	defer backend.Close()

	entry := backend.Backend()
	if entry.BaseURL != backend.URL() {
		t.Errorf("Backend().BaseURL = %q, want %q", entry.BaseURL, backend.URL())
	}
	// The entry must be a config block a real tree accepts.
	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}
	config := apiengine.DefaultConfig()
	config.Backends["api"] = entry
	if err := config.Validate(problems); err != nil {
		t.Errorf("the fake's config entry must validate: %v", err)
	}
}

func TestProblemResponseBuildsTheEnvelope(t *testing.T) {
	t.Parallel()

	full := testhelper.ProblemResponse(testhelper.ProblemOptions{
		Type: "https://x", Title: "T", Status: 409,
		Detail: "d", Instance: "urn:1", Recoverable: true,
		Data: map[string]any{"k": "v"},
	})
	if full.Detail == nil || *full.Detail != "d" {
		t.Errorf("detail = %v, want d", full.Detail)
	}
	if full.Instance == nil || *full.Instance != "urn:1" {
		t.Errorf("instance = %v, want urn:1", full.Instance)
	}
	if !full.Recoverable || full.Status != 409 {
		t.Errorf("envelope = %+v, want the declared members", full)
	}

	// Blank optional members stay absent, and data is never nil — a nil map
	// would render as `null` where C0 requires an object.
	bare := testhelper.ProblemResponse(testhelper.ProblemOptions{Type: "https://x", Title: "T"})
	if bare.Detail != nil {
		t.Errorf("detail = %v, want absent for a blank option", bare.Detail)
	}
	if bare.Instance != nil {
		t.Errorf("instance = %v, want absent for a blank option", bare.Instance)
	}
	if bare.Data == nil {
		t.Error("data must be an empty object, never nil")
	}
}

// A canned route must be decodable by the very classifier it is a fixture for.
func TestCannedRouteIsClassifiedAsAProblem(t *testing.T) {
	t.Parallel()

	route := testhelper.Canned(testhelper.ProblemOptions{
		Type: "https://x/quota", Title: "Quota", Status: http.StatusTooManyRequests,
		Data: map[string]any{"limit": float64(5)},
	})
	if route.Status != http.StatusTooManyRequests {
		t.Errorf("route status = %d, want the envelope's own status", route.Status)
	}
	if route.Header.Get("Content-Type") != "application/problem+json" {
		t.Errorf("Content-Type = %q, want application/problem+json", route.Header.Get("Content-Type"))
	}

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{"/q": route},
	})
	defer backend.Close()

	response, body := get(t, backend.URL()+"/q")
	if outcome := apiengine.Classify(response.StatusCode, nil); outcome != apiengine.OutcomeProblem {
		t.Errorf("outcome = %s, want problem", outcome)
	}
	decoded, ok := apiengine.DecodeProblem(body)
	if !ok {
		t.Fatalf("canned body %s did not decode as a problem", body)
	}
	if decoded.Data["limit"] != float64(5) {
		t.Errorf("data.limit = %v, want 5", decoded.Data["limit"])
	}
}

func TestFakeRetriever(t *testing.T) {
	t.Parallel()

	retriever := testhelper.NewFakeRetriever(map[string]string{"alpha": "token-alpha"})
	ctx := context.Background()

	token, err := retriever.Token(ctx, "alpha")
	if err != nil {
		t.Fatalf("Token(alpha): %v", err)
	}
	if token.Value != "token-alpha" || token.Resource != "alpha" {
		t.Errorf("token = %+v, want the canned value for alpha", token)
	}
	if !token.ExpiresAt.After(token.IssuedAt) {
		t.Error("the canned token must not already be expired")
	}

	if _, err := retriever.Token(ctx, "absent"); err == nil {
		t.Error("Token(absent): want an error, got none")
	}

	failure := errors.New("the IdP is down")
	retriever.FailResource("alpha", failure)
	if _, err := retriever.Token(ctx, "alpha"); !errors.Is(err, failure) {
		t.Errorf("Token after FailResource = %v, want the injected failure", err)
	}

	asked := retriever.Asked()
	if !slices.Equal(asked, []string{"alpha", "absent", "alpha"}) {
		t.Errorf("Asked() = %v, want every request in order", asked)
	}
	// The log is a copy.
	asked[0] = "mutated"
	if retriever.Asked()[0] != "alpha" {
		t.Error("Asked() must return a copy, not the fake's own slice")
	}
}

func TestSampleErrorPortalAndProblems(t *testing.T) {
	t.Parallel()

	portal := testhelper.SampleErrorPortal()
	if portal.Host == "" || portal.Scheme == "" {
		t.Errorf("SampleErrorPortal = %+v, want a complete portal", portal)
	}

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("NewProblems: %v", err)
	}
	if problems.Registry().Portal() != portal {
		t.Error("NewProblems must bind the sample portal")
	}
	if _, found := problems.Registry().Lookup(apiengine.ProblemTransport); !found {
		t.Error("NewProblems must register the engine's own types")
	}
}

func TestNewFakeTree(t *testing.T) {
	t.Parallel()

	route := map[string]testhelper.Route{"/x": {Status: http.StatusOK, Body: map[string]any{"ok": true}}}
	alpha := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Routes: route})
	beta := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Routes: route})

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"alpha": alpha, "beta": beta},
		Tokens:   map[string]string{"alpha": "token-alpha", "beta": "token-beta"},
	})
	if err != nil {
		t.Fatalf("NewFakeTree: %v", err)
	}

	if got := tree.Tree.Names(); !slices.Equal(got, []string{"alpha", "beta"}) {
		t.Errorf("Names() = %v, want both backends", got)
	}
	if tree.Retriever == nil {
		t.Fatal("a tree built with tokens must expose its retriever")
	}
	if tree.Problems == nil {
		t.Fatal("the tree must expose the factory it mints errors through")
	}

	client, err := tree.Tree.Backend("alpha")
	if err != nil {
		t.Fatalf("resolve alpha: %v", err)
	}
	if _, err := apiengine.Execute[map[string]any](context.Background(), client,
		apiengine.Request{Path: "/x"}); err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if got := alpha.Requests()[0].Authorization(); got != "Bearer token-alpha" {
		t.Errorf("Authorization = %q, want alpha's own token", got)
	}

	// Close shuts every backend down: a second call to a closed fake fails.
	tree.Close()
	if _, err := http.Get(alpha.URL() + "/x"); err == nil { //nolint:bodyclose,noctx,gosec // proving the server is closed
		t.Error("Close must shut the fake backends down")
	}
}

func TestNewFakeTreeWithoutTokens(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{"/x": {Status: http.StatusOK, Body: map[string]any{"ok": true}}},
	})
	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"open": backend},
	})
	if err != nil {
		t.Fatalf("NewFakeTree: %v", err)
	}
	defer tree.Close()

	if tree.Retriever != nil {
		t.Error("a tree built without tokens must expose no retriever")
	}
	client, err := tree.Tree.Backend("open")
	if err != nil {
		t.Fatalf("resolve open: %v", err)
	}
	if _, err := apiengine.Execute[map[string]any](context.Background(), client,
		apiengine.Request{Path: "/x"}); err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if got := backend.Requests()[0].Authorization(); got != "" {
		t.Errorf("Authorization = %q, want none", got)
	}
}

// A fixture author who typos a backend name gets told, rather than a tree that
// silently registers a backend called "".
func TestNewFakeTreeRejectsABlankBackendName(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
	defer backend.Close()

	_, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"": backend},
	})
	if err == nil {
		t.Fatal("NewFakeTree with a blank backend name: want an error, got none")
	}
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{Title: "Api configuration invalid"})
}

// A consumer registers its own problem types on the same factory, so it exports
// ONE catalog — and a type whose id collides with an engine problem is refused
// rather than silently shadowing it.
func TestNewFakeTreeRegistersExtraProblemTypes(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{})
	defer backend.Close()

	own := problem.Type{ID: "consumer-own", Title: "Consumer own", Version: "v1", Status: 418}
	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends:      map[string]*testhelper.FakeBackend{"api": backend},
		ExtraProblems: []problem.Type{own},
	})
	if err != nil {
		t.Fatalf("NewFakeTree: %v", err)
	}
	if _, found := tree.Problems.Registry().Lookup("consumer-own"); !found {
		t.Error("the consumer type is missing from the tree factory")
	}

	collision := problem.Type{ID: apiengine.ProblemTransport, Title: "Mine", Version: "v1", Status: 500}
	if _, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends:      map[string]*testhelper.FakeBackend{"api": backend},
		ExtraProblems: []problem.Type{collision},
	}); err == nil {
		t.Error("NewFakeTree with a colliding problem id: want an error, got none")
	}
}
