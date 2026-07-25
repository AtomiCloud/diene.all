package apiengine_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-api-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestProblemTypesAreDeclaredOnce(t *testing.T) {
	t.Parallel()

	types := apiengine.ProblemTypes()
	if len(types) == 0 {
		t.Fatal("ProblemTypes: want the engine's declarations, got none")
	}

	seen := map[string]bool{}
	for _, declared := range types {
		if seen[declared.ID] {
			t.Errorf("problem id %q is declared twice", declared.ID)
		}
		seen[declared.ID] = true

		if declared.Version != apiengine.ProblemVersion {
			t.Errorf("%s version = %q, want %q", declared.ID, declared.Version, apiengine.ProblemVersion)
		}
		if declared.Title == "" {
			t.Errorf("%s declares no title", declared.ID)
		}
		if declared.Status < 400 || declared.Status > 599 {
			t.Errorf("%s status = %d, want a 4xx or 5xx", declared.ID, declared.Status)
		}
	}

	// Every exported id must actually be declared, or a Raise on it silently
	// degrades to the uncatalogued fallback.
	for _, id := range []string{
		apiengine.ProblemTransport,
		apiengine.ProblemResponseUnreadable,
		apiengine.ProblemResponseUndecodable,
		apiengine.ProblemResponseNotProblem,
		apiengine.ProblemBackendUnregistered,
		apiengine.ProblemRequestUnbuildable,
		apiengine.ProblemCredentialsUnavailable,
		apiengine.ProblemConfigInvalid,
	} {
		if !seen[id] {
			t.Errorf("exported id %q is not declared in ProblemTypes", id)
		}
	}
}

func TestNewProblemsAcceptsConsumerTypes(t *testing.T) {
	t.Parallel()

	extra := problem.Type{ID: "consumer-own", Title: "Consumer own", Version: "v1", Status: 418}
	problems, err := apiengine.NewProblems(testhelper.SampleErrorPortal(), extra)
	if err != nil {
		t.Fatalf("NewProblems: %v", err)
	}

	// One registry, so a consumer exports ONE catalog.
	if _, found := problems.Registry().Lookup("consumer-own"); !found {
		t.Error("the consumer's own type is missing from the registry")
	}
	if _, found := problems.Registry().Lookup(apiengine.ProblemTransport); !found {
		t.Error("the engine's own type is missing from the registry")
	}

	err = problems.Raise("consumer-own", "teapot", nil)
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{Title: "Consumer own", Status: 418})
}

func TestNewProblemsRejectsACollidingType(t *testing.T) {
	t.Parallel()

	collision := problem.Type{ID: apiengine.ProblemTransport, Title: "Mine", Version: "v1", Status: 500}
	if _, err := apiengine.NewProblems(testhelper.SampleErrorPortal(), collision); err == nil {
		t.Error("NewProblems with a colliding id: want an error, got none")
	}
}

func TestRaiseMintsTheRegisteredEnvelope(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	err = problems.Raise(apiengine.ProblemTransport, "the backend vanished",
		map[string]any{"backend": "billing"})
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Title:  "Backend transport failed",
		Status: 502,
		Detail: "the backend vanished",
		Data:   map[string]any{"backend": "billing"},
	})
	if !strings.Contains(envelope.Type, "/"+apiengine.ProblemVersion+"/"+apiengine.ProblemTransport) {
		t.Errorf("type URI = %q, want the versioned single-source form", envelope.Type)
	}
	if !envelope.Recoverable {
		t.Error("transport is declared recoverable; want the flag carried through")
	}
}

func TestRaiseIsTotalOnAnUnknownID(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	// A failure to describe a failure must never replace it.
	err = problems.Raise("never-registered", "still has to surface", nil)
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{
		Detail: "still has to surface",
	})
	if envelope.Status != 500 {
		t.Errorf("uncatalogued status = %d, want 500", envelope.Status)
	}
}

func TestRaiseFromKeepsTheCauseTraversable(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	cause := errors.New("dial tcp: connection refused")
	err = problems.RaiseFrom(apiengine.ProblemTransport, cause, "no route", nil)
	if !errors.Is(err, cause) {
		t.Error("errors.Is must traverse into the wrapped cause")
	}
	testhelper.AssertProblem(t, err, testhelper.ProblemOptions{Title: "Backend transport failed"})
}

func TestRaiseWithNilDataYieldsAnEmptyObject(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	err = problems.Raise(apiengine.ProblemConfigInvalid, "bad config", nil)
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{})
	if envelope.Data == nil {
		t.Error("data: want an empty object, got nil")
	}
	if len(envelope.Data) != 0 {
		t.Errorf("data = %v, want empty", envelope.Data)
	}
}

func TestCatalogCarriesEveryDeclaredType(t *testing.T) {
	t.Parallel()

	problems, err := testhelper.NewProblems()
	if err != nil {
		t.Fatalf("problems: %v", err)
	}

	catalog, err := problems.Catalog()
	if err != nil {
		t.Fatalf("Catalog: %v", err)
	}
	entries := catalog.Entries()
	if len(entries) != len(apiengine.ProblemTypes()) {
		t.Errorf("catalog entries = %d, want %d", len(entries), len(apiengine.ProblemTypes()))
	}
	if _, found := catalog.Lookup(apiengine.ProblemTransport); !found {
		t.Error("the catalog omits the transport problem")
	}
	// The generic set is the consumer's decision, not the engine's.
	if _, found := catalog.Lookup("entity-not-found"); found {
		t.Error("the catalog must not add the portable generics by itself")
	}
	if content := catalog.ToCRDContent(); len(content) != len(entries) {
		t.Errorf("CRD content rows = %d, want %d", len(content), len(entries))
	}
}

func TestRegistryPortalIsTheConsumersOwn(t *testing.T) {
	t.Parallel()

	portal := problem.ErrorPortal{
		Scheme: "https", Host: "docs.example.com",
		Landscape: "prod", Platform: "api", Service: "billing", Module: "core",
	}
	problems, err := apiengine.NewProblems(portal)
	if err != nil {
		t.Fatalf("NewProblems: %v", err)
	}

	if problems.Registry().Portal() != portal {
		t.Error("the registry must carry the consumer's own portal")
	}
	err = problems.Raise(apiengine.ProblemTransport, "x", nil)
	envelope := testhelper.AssertProblem(t, err, testhelper.ProblemOptions{})
	// A failure raised inside a consumer is attributed to that consumer's
	// portal, not to this library.
	if !strings.HasPrefix(envelope.Type, "https://docs.example.com/docs/prod/api/billing/core/") {
		t.Errorf("type URI = %q, want the consumer's portal", envelope.Type)
	}
}
