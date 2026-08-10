package authengine_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestProblemTypesAreUniqueAndVersioned(t *testing.T) {
	t.Parallel()

	seen := map[string]bool{}
	for _, declared := range authengine.ProblemTypes() {
		if seen[declared.ID] {
			t.Fatalf("problem id %q is declared twice", declared.ID)
		}
		seen[declared.ID] = true
		if declared.Version != authengine.ProblemVersion {
			t.Fatalf("problem %q must carry version %q, got %q",
				declared.ID, authengine.ProblemVersion, declared.Version)
		}
		if declared.Status < 400 {
			t.Fatalf("problem %q must carry a failure status, got %d", declared.ID, declared.Status)
		}
		if declared.Title == "" {
			t.Fatalf("problem %q must carry a title", declared.ID)
		}
	}
	if len(seen) != len(authengine.ProblemTypes()) {
		t.Fatal("expected every declared problem type to be distinct")
	}
}

func TestNewProblemsRejectsDuplicateRegistration(t *testing.T) {
	t.Parallel()

	registry, err := problem.NewRegistry(testhelper.SampleErrorPortal(), authengine.ProblemTypes()...)
	requireNoError(t, err)

	if err := registry.Register(authengine.ProblemTypes()[0]); err == nil {
		t.Fatal("expected registering a declared id twice to be rejected")
	}
}

func TestRaiseMintsTheRegisteredProblem(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)

	err := problems.Raise(authengine.ProblemOwnershipDenied, "denied", map[string]any{"subject": "user-1"})
	envelope := requireProblem(t, err, authengine.ProblemOwnershipDenied)

	if envelope.Status != 403 {
		t.Fatalf("expected status 403, got %d", envelope.Status)
	}
	if envelope.Detail == nil || *envelope.Detail != "denied" {
		t.Fatalf("expected the detail to be carried, got %v", envelope.Detail)
	}
	if envelope.Data["subject"] != "user-1" {
		t.Fatalf("expected the data payload to be carried, got %v", envelope.Data)
	}
}

func TestRaiseDefaultsAnAbsentDataPayload(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)

	envelope := requireProblem(t,
		problems.Raise(authengine.ProblemTokenExpired, "expired", nil),
		authengine.ProblemTokenExpired)

	if envelope.Data == nil {
		t.Fatal("expected an absent data payload to render as an empty object")
	}
}

func TestRaiseFromKeepsTheCauseTraversable(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)

	err := problems.RaiseFrom(authengine.ProblemProviderUnavailable, errFake, "unreachable", nil)
	requireProblem(t, err, authengine.ProblemProviderUnavailable)

	if !errors.Is(err, errFake) {
		t.Fatal("expected errors.Is to traverse into the wrapped cause")
	}
}

func TestRaiseFallsBackForAnUnregisteredID(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)

	envelope := requireProblem(t,
		problems.Raise("not-a-declared-problem", "mystery", map[string]any{"hint": "typo"}),
		problem.UncataloguedProblemID)

	if envelope.Status != 500 {
		t.Fatalf("expected an uncatalogued fallback to be 500, got %d", envelope.Status)
	}
	if envelope.Data["hint"] != "typo" {
		t.Fatalf("expected the fallback to keep the data payload, got %v", envelope.Data)
	}
}

func TestRaiseFallsBackWhenThePortalCannotBuildAURI(t *testing.T) {
	t.Parallel()

	broken := testhelper.SampleErrorPortal()
	broken.Host = "docs.example/invalid"

	problems, err := authengine.NewProblems(broken)
	requireNoError(t, err)

	// A portal that cannot mint a type URI cannot mint the uncatalogued one either,
	// so the envelope degrades to the RFC 9457 default type — but it is still a
	// problem-typed 500 that carries the original detail, which is the guarantee
	// that matters: describing a failure must never replace it.
	envelope := requireProblem(t,
		problems.Raise(authengine.ProblemTokenExpired, "expired", nil),
		"about:blank")

	if envelope.Status != 500 {
		t.Fatalf("expected the fallback to be 500, got %d", envelope.Status)
	}
	if envelope.Detail == nil || *envelope.Detail != "expired" {
		t.Fatalf("expected the fallback to keep the detail, got %v", envelope.Detail)
	}
}

func TestRegistryExposesTheDeclaredTypes(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)

	if got := len(problems.Registry().Entries()); got != len(authengine.ProblemTypes()) {
		t.Fatalf("expected %d registered types, got %d", len(authengine.ProblemTypes()), got)
	}
	if _, found := problems.Registry().Lookup(authengine.ProblemOwnershipDenied); !found {
		t.Fatal("expected the ownership-denied type to be registered")
	}
}

func TestCatalogCarriesTheEngineProblemsOnly(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)

	catalog, err := problems.Catalog()
	requireNoError(t, err)

	if _, found := catalog.Lookup(authengine.ProblemOwnershipDenied); !found {
		t.Fatal("expected the engine problems to be catalogued")
	}
	// Which generics a service publishes is the service's call, not the engine's.
	if _, found := catalog.Lookup("entity-not-found"); found {
		t.Fatal("expected the engine not to decide the consumer's generic set")
	}
	requireNoError(t, catalog.AddGenerics())
	if _, found := catalog.Lookup("entity-not-found"); !found {
		t.Fatal("expected a consumer to be able to add the generics itself")
	}
	if len(catalog.ToCRDContent()) == 0 {
		t.Fatal("expected the catalog to render Problem CR content")
	}
}

func TestCatalogFailsOnAPortalThatCannotBuildURIs(t *testing.T) {
	t.Parallel()

	broken := testhelper.SampleErrorPortal()
	broken.Landscape = ""

	problems, err := authengine.NewProblems(broken)
	requireNoError(t, err)

	if _, err := problems.Catalog(); err == nil {
		t.Fatal("expected a catalog built from an invalid portal to be rejected")
	}
}

func TestNewProblemsRegistersConsumerTypesOnOneRegistry(t *testing.T) {
	t.Parallel()

	domain := problem.Type{ID: "booking-locked", Title: "Booking locked", Version: "v1", Status: 409}

	problems, err := authengine.NewProblems(testhelper.SampleErrorPortal(), domain)
	requireNoError(t, err)

	// One registry means one exported catalog: a consumer's domain problems and the
	// engine's appear in the same published error portal.
	if _, found := problems.Registry().Lookup("booking-locked"); !found {
		t.Fatal("expected the consumer type to be registered")
	}
	if _, found := problems.Registry().Lookup(authengine.ProblemOwnershipDenied); !found {
		t.Fatal("expected the engine types to still be registered")
	}
	requireProblem(t, problems.Raise("booking-locked", "locked", nil), "booking-locked")

	catalog, err := problems.Catalog()
	requireNoError(t, err)
	if _, found := catalog.Lookup("booking-locked"); !found {
		t.Fatal("expected the consumer type to be catalogued")
	}
}

func TestNewProblemsRejectsAConsumerTypeThatShadowsAnEngineProblem(t *testing.T) {
	t.Parallel()

	// Silently shadowing an engine problem would make the same failure report two
	// different contracts depending on registration order.
	_, err := authengine.NewProblems(testhelper.SampleErrorPortal(), problem.Type{
		ID: authengine.ProblemOwnershipDenied, Title: "Mine now", Version: "v1", Status: 403,
	})
	if err == nil {
		t.Fatal("expected a colliding consumer problem id to be rejected")
	}
}
