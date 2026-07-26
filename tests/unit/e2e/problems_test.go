package e2e_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestProblemTypesAreStableAndVersioned(t *testing.T) {
	t.Parallel()

	types := e2e.ProblemTypes()
	if len(types) != 10 {
		t.Fatalf("ProblemTypes() length = %d, want 10", len(types))
	}
	want := []string{
		e2e.ProblemDriverUnconfigured,
		e2e.ProblemArtifactMissing,
		e2e.ProblemInvocationFailed,
		e2e.ProblemJourneyEmpty,
		e2e.ProblemStepFailed,
		e2e.ProblemParityMismatch,
		e2e.ProblemTargetIncomplete,
		e2e.ProblemTargetUnreadable,
		e2e.ProblemFixtureInvalid,
		e2e.ProblemFixtureUnwritable,
	}
	for index, declared := range types {
		if declared.ID != want[index] {
			t.Fatalf("ProblemTypes()[%d].ID = %q, want %q", index, declared.ID, want[index])
		}
		if declared.Version != e2e.ProblemVersion {
			t.Fatalf("%q version = %q, want %q", declared.ID, declared.Version, e2e.ProblemVersion)
		}
		if declared.Title == "" {
			t.Fatalf("%q has no title", declared.ID)
		}
		if declared.Status < 400 {
			t.Fatalf("%q status = %d, want a failure status", declared.ID, declared.Status)
		}
	}
}

func TestNewProblemsRejectsCollidingExtraType(t *testing.T) {
	t.Parallel()

	_, err := e2e.NewProblems(samplePortal(), problem.Type{
		ID:      e2e.ProblemStepFailed,
		Title:   "Shadowed",
		Version: "v1",
		Status:  422,
	})
	var duplicate *problem.DuplicateTypeError
	if !errors.As(err, &duplicate) {
		t.Fatalf("NewProblems() error = %v, want a DuplicateTypeError", err)
	}
}

func TestNewProblemsAcceptsConsumerType(t *testing.T) {
	t.Parallel()

	problems, err := e2e.NewProblems(samplePortal(), problem.Type{
		ID:      "consumer-specific",
		Title:   "Consumer specific",
		Version: "v1",
		Status:  418,
	})
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	if got := len(problems.Registry().Entries()); got != 11 {
		t.Fatalf("registry entries = %d, want 11", got)
	}
	if problems.Registry().Portal() != samplePortal() {
		t.Fatalf("registry portal = %+v, want the supplied portal", problems.Registry().Portal())
	}
}

func TestRaiseBuildsSingleSourceTypeURI(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	err := problems.Raise(e2e.ProblemJourneyEmpty, "nothing to run", map[string]any{"journey": "smoke"})
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("Raise() error = %v, want a problem-typed error", err)
	}
	wantURI, uriErr := problem.TypeURI(samplePortal(), e2e.ProblemVersion, e2e.ProblemJourneyEmpty)
	if uriErr != nil {
		t.Fatalf("TypeURI() error = %v", uriErr)
	}
	if typed.Problem.Type != wantURI {
		t.Fatalf("problem type = %q, want %q", typed.Problem.Type, wantURI)
	}
	if typed.Problem.Status != 422 {
		t.Fatalf("problem status = %d, want 422", typed.Problem.Status)
	}
	if typed.Problem.Detail == nil || *typed.Problem.Detail != "nothing to run" {
		t.Fatalf("problem detail = %v, want %q", typed.Problem.Detail, "nothing to run")
	}
	if typed.Problem.Data["journey"] != "smoke" {
		t.Fatalf("problem data = %v, want journey smoke", typed.Problem.Data)
	}
}

func TestRaiseWithoutDataStillCarriesAnEnvelope(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	err := problems.Raise(e2e.ProblemStepFailed, "missed", nil)
	if data := problemData(t, err); data == nil || len(data) != 0 {
		t.Fatalf("problem data = %v, want an empty map", data)
	}
}

func TestRaiseFromKeepsTheCauseTraversable(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	err := problems.RaiseFrom(e2e.ProblemInvocationFailed, errBoom, "could not run", nil)
	if !errors.Is(err, errBoom) {
		t.Fatal("errors.Is(err, errBoom) = false, want true")
	}
	if got := problemID(t, err); got != e2e.ProblemInvocationFailed {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemInvocationFailed)
	}
}

func TestRaiseIsTotalOnAnUnregisteredID(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	err := problems.Raise("not-a-harness-problem", "unknown", map[string]any{"seen": true})
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("Raise() error = %v, want a problem-typed error", err)
	}
	if !strings.HasSuffix(typed.Problem.Type, "/"+problem.UncataloguedProblemID) {
		t.Fatalf("problem type = %q, want the uncatalogued fallback", typed.Problem.Type)
	}
	if typed.Problem.Status != 500 {
		t.Fatalf("problem status = %d, want 500", typed.Problem.Status)
	}
	if seen, marked := typed.Problem.Data["seen"].(bool); !marked || !seen {
		t.Fatalf("problem data = %v, want the caller payload preserved", typed.Problem.Data)
	}
}

func TestRaiseFallsBackWhenTheTypeURICannotBeBuilt(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, brokenPortal())
	err := problems.Raise(e2e.ProblemStepFailed, "unbuildable", nil)
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("Raise() error = %v, want a problem-typed error", err)
	}
	if typed.Problem.Status != 500 {
		t.Fatalf("problem status = %d, want the 500 fallback", typed.Problem.Status)
	}
	if typed.Problem.Detail == nil || *typed.Problem.Detail != "unbuildable" {
		t.Fatalf("problem detail = %v, want the caller detail preserved", typed.Problem.Detail)
	}
}

func TestCatalogCarriesEveryRegisteredType(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	catalog, err := problems.Catalog()
	if err != nil {
		t.Fatalf("Catalog() error = %v", err)
	}
	entries := catalog.Entries()
	if len(entries) != len(e2e.ProblemTypes()) {
		t.Fatalf("catalog entries = %d, want %d", len(entries), len(e2e.ProblemTypes()))
	}
	for _, entry := range entries {
		if entry.TypeURI == "" {
			t.Fatalf("catalog entry %q has no type URI", entry.ID)
		}
	}
}

func TestCatalogRefusesAnUnbuildablePortal(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, brokenPortal())
	if _, err := problems.Catalog(); err == nil {
		t.Fatal("Catalog() error = nil, want a refusal")
	}
}
