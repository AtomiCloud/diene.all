package apiengine_test

import (
	"context"
	"errors"
	"net/http"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

type user struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// The per-lib DoD in one test: all three cases, proven against a mock
// Problem-envelope response, with the `data` extension surviving to (T, error).
func TestThreeCaseClassificationEndToEnd(t *testing.T) {
	t.Parallel()

	const quotaType = "https://docs.example.com/docs/prod/api/billing/quota/v1/quota-exceeded"
	quotaData := map[string]any{
		"limit":     float64(100),
		"used":      float64(101),
		"resetsAt":  "2026-07-26T00:00:00Z",
		"offenders": []any{"alpha", "beta"},
	}

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/success": {Status: http.StatusOK, Body: user{ID: "u-1", Name: "Ada"}},
			"/problem": testhelper.Canned(testhelper.ProblemOptions{
				Type:        quotaType,
				Title:       "Quota exceeded",
				Status:      http.StatusTooManyRequests,
				Detail:      "the monthly quota is spent",
				Instance:    "urn:call:9f2",
				Recoverable: true,
				Data:        quotaData,
			}),
			"/broken": {Status: http.StatusInternalServerError, Body: `{"oh":"no"}`},
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"billing": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	client, err := tree.Tree.Backend("billing")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}
	ctx := context.Background()

	t.Run("2xx yields the value and a nil error", func(t *testing.T) {
		got, err := apiengine.Execute[user](ctx, client, apiengine.Request{Path: "/success"})
		if err != nil {
			t.Fatalf("Execute: unexpected error %v", err)
		}
		if got != (user{ID: "u-1", Name: "Ada"}) {
			t.Errorf("Execute = %+v, want the decoded user", got)
		}
	})

	t.Run("4xx yields the backend's own envelope with its data extension", func(t *testing.T) {
		got, err := apiengine.Execute[user](ctx, client, apiengine.Request{Path: "/problem"})
		if err == nil {
			t.Fatal("Execute: want a problem-typed error, got none")
		}
		if got != (user{}) {
			t.Errorf("Execute value = %+v, want the zero value on a problem", got)
		}

		// The envelope must arrive unmodified: the backend published this
		// contract, and re-minting it would strip the typed payload.
		envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
			Type:     quotaType,
			Title:    "Quota exceeded",
			Status:   http.StatusTooManyRequests,
			Detail:   "the monthly quota is spent",
			Instance: "urn:call:9f2",
			Data:     quotaData,
		})
		if !envelope.Recoverable {
			t.Error("recoverable flag: want true, got false")
		}
		if envelope.Data["limit"] != float64(100) {
			t.Errorf("data.limit = %v, want 100", envelope.Data["limit"])
		}
	})

	t.Run("5xx yields the engine's transport problem", func(t *testing.T) {
		_, err := apiengine.Execute[user](ctx, client, apiengine.Request{Path: "/broken"})
		if err == nil {
			t.Fatal("Execute: want a transport error, got none")
		}
		envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
			Title:  "Backend transport failed",
			Status: http.StatusBadGateway,
		})
		if envelope.Data["backend"] != "billing" {
			t.Errorf("data.backend = %v, want billing", envelope.Data["backend"])
		}
		if envelope.Data["status"] != http.StatusInternalServerError {
			t.Errorf("data.status = %v, want 500", envelope.Data["status"])
		}
	})
}

func TestClassify(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name      string
		status    int
		transport error
		want      apiengine.Outcome
	}{
		{"200 is success", 200, nil, apiengine.OutcomeSuccess},
		{"201 is success", 201, nil, apiengine.OutcomeSuccess},
		{"299 is success", 299, nil, apiengine.OutcomeSuccess},
		{"400 is a problem", 400, nil, apiengine.OutcomeProblem},
		{"404 is a problem", 404, nil, apiengine.OutcomeProblem},
		{"499 is a problem", 499, nil, apiengine.OutcomeProblem},
		{"500 is transport", 500, nil, apiengine.OutcomeTransport},
		{"503 is transport", 503, nil, apiengine.OutcomeTransport},
		{"300 is transport", 300, nil, apiengine.OutcomeTransport},
		{"100 is transport", 100, nil, apiengine.OutcomeTransport},
		{"a transport error wins over a 200", 200, errors.New("dial"), apiengine.OutcomeTransport},
		{"a transport error wins over a 404", 404, errors.New("reset"), apiengine.OutcomeTransport},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			if got := apiengine.Classify(testCase.status, testCase.transport); got != testCase.want {
				t.Errorf("Classify(%d, %v) = %s, want %s",
					testCase.status, testCase.transport, got, testCase.want)
			}
		})
	}
}

func TestOutcomeString(t *testing.T) {
	t.Parallel()

	cases := map[apiengine.Outcome]string{
		apiengine.OutcomeSuccess:   "success",
		apiengine.OutcomeProblem:   "problem",
		apiengine.OutcomeTransport: "transport",
		apiengine.Outcome(99):      "unknown",
	}
	for outcome, want := range cases {
		if got := outcome.String(); got != want {
			t.Errorf("Outcome(%d).String() = %q, want %q", int(outcome), got, want)
		}
	}
}

func TestDecodeProblem(t *testing.T) {
	t.Parallel()

	t.Run("decodes a full envelope with its data extension", func(t *testing.T) {
		t.Parallel()
		body := []byte(`{"type":"https://x/y","title":"Nope","status":409,` +
			`"detail":"clash","instance":"urn:1","recoverable":true,"data":{"field":"name"}}`)
		decoded, ok := apiengine.DecodeProblem(body)
		if !ok {
			t.Fatal("DecodeProblem: want ok, got false")
		}
		if decoded.Type != "https://x/y" || decoded.Status != 409 || !decoded.Recoverable {
			t.Errorf("DecodeProblem = %+v, want the envelope's own members", decoded)
		}
		if decoded.Data["field"] != "name" {
			t.Errorf("data.field = %v, want name", decoded.Data["field"])
		}
	})

	t.Run("accepts an envelope carrying only a title", func(t *testing.T) {
		t.Parallel()
		if _, ok := apiengine.DecodeProblem([]byte(`{"title":"Nope"}`)); !ok {
			t.Error("DecodeProblem: want ok for a title-only envelope")
		}
	})

	t.Run("rejects a body that is not a problem envelope", func(t *testing.T) {
		t.Parallel()
		rejected := []string{
			`{"error":"nope"}`,
			`{}`,
			`[]`,
			`not json at all`,
			``,
		}
		for _, body := range rejected {
			if _, ok := apiengine.DecodeProblem([]byte(body)); ok {
				t.Errorf("DecodeProblem(%q): want false, got true", body)
			}
		}
	})

	t.Run("rejects an envelope whose members are the wrong type", func(t *testing.T) {
		t.Parallel()
		if _, ok := apiengine.DecodeProblem([]byte(`{"type":"https://x","status":"409"}`)); ok {
			t.Error("DecodeProblem: want false for a string status")
		}
	})
}

// A 4xx from a backend that is not C0-conformant must be named as such rather
// than surfaced as a plausible-looking envelope nobody published.
func TestNonConformantClientErrorIsReported(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/legacy": {Status: http.StatusBadRequest, Body: `{"message":"bad input"}`},
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"legacy": backend},
	})
	if err != nil {
		t.Fatalf("build tree: %v", err)
	}
	client, err := tree.Tree.Backend("legacy")
	if err != nil {
		t.Fatalf("resolve backend: %v", err)
	}

	_, err = apiengine.Execute[user](context.Background(), client, apiengine.Request{Path: "/legacy"})
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend error was not a problem envelope",
		Status: http.StatusBadGateway,
	})
	if envelope.Data["status"] != http.StatusBadRequest {
		t.Errorf("data.status = %v, want 400", envelope.Data["status"])
	}
}

// A 2xx body that does not fit the caller's type is the caller's problem to
// see, not a silent zero value.
func TestUndecodableSuccessIsReported(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/wrong": {Status: http.StatusOK, Body: `["not","an","object"]`},
			"/empty": {Status: http.StatusNoContent},
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
	ctx := context.Background()

	_, err = apiengine.Execute[user](ctx, client, apiengine.Request{Path: "/wrong"})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend response undecodable",
		Status: http.StatusBadGateway,
	})

	// A 204 leaves the caller its zero value rather than failing to decode
	// nothing.
	got, err := apiengine.Execute[user](ctx, client, apiengine.Request{Path: "/empty"})
	if err != nil {
		t.Errorf("Execute on 204: unexpected error %v", err)
	}
	if got != (user{}) {
		t.Errorf("Execute on 204 = %+v, want the zero value", got)
	}
}

// Send discards the body but keeps the classification.
func TestSend(t *testing.T) {
	t.Parallel()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/ok": {Status: http.StatusAccepted, Body: `{"ignored":true}`},
			"/no": testhelper.Canned(testhelper.ProblemOptions{
				Type: "https://x/denied", Title: "Denied", Status: http.StatusForbidden,
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
	ctx := context.Background()

	if sendErr := apiengine.Send(ctx, client, apiengine.Request{
		Method: http.MethodPost, Path: "/ok", Body: user{ID: "u-2"},
	}); sendErr != nil {
		t.Errorf("Send: unexpected error %v", sendErr)
	}

	err = apiengine.Send(ctx, client, apiengine.Request{Method: http.MethodPost, Path: "/no"})
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Denied",
		Status: http.StatusForbidden,
	})
}

// Execute is a package function, so a nil client is reachable in a way a method
// receiver would not be; it must not panic.
func TestExecuteRejectsANilClient(t *testing.T) {
	t.Parallel()

	_, err := apiengine.Execute[user](context.Background(), nil, apiengine.Request{})
	if err == nil {
		t.Fatal("Execute(nil): want an error, got none")
	}
	var carried *problem.Error
	if errors.As(err, &carried) {
		t.Error("Execute(nil): want a plain error, got a problem-typed one")
	}
}
