package problem_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func testPortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.example.atomi.cloud",
		Landscape: "raichu",
		Platform:  "go",
		Service:   "user",
		Module:    "api",
	}
}

func TestNewRegistryPrepopulates(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.EntityNotFound(), problem.Conflict())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(registry.Entries()) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(registry.Entries()))
	}
	if registry.Portal() != testPortal() {
		t.Fatalf("portal not preserved: %+v", registry.Portal())
	}
}

func TestNewRegistryRejectsDuplicates(t *testing.T) {
	t.Parallel()
	_, err := problem.NewRegistry(testPortal(), problem.Conflict(), problem.Conflict())
	var dupErr *problem.DuplicateTypeError
	if !errors.As(err, &dupErr) {
		t.Fatalf("expected *DuplicateTypeError, got %v", err)
	}
	if dupErr.ID != "conflict" || dupErr.Error() == "" {
		t.Fatalf("unexpected duplicate error: %+v", dupErr)
	}
}

func TestRegistryLookupAndRequire(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.EntityNotFound())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	found, ok := registry.Lookup("entity-not-found")
	if !ok || found.Title != "Entity not found" {
		t.Fatalf("lookup failed: %+v ok=%v", found, ok)
	}
	if _, ok := registry.Lookup("missing"); ok {
		t.Fatal("expected missing lookup to report absent")
	}
	required, err := registry.Require("entity-not-found")
	if err != nil || required.ID != "entity-not-found" {
		t.Fatalf("require failed: %+v err=%v", required, err)
	}
	_, err = registry.Require("missing")
	var unknownErr *problem.UnknownTypeError
	if !errors.As(err, &unknownErr) {
		t.Fatalf("expected *UnknownTypeError, got %v", err)
	}
	if unknownErr.ID != "missing" || unknownErr.Error() == "" {
		t.Fatalf("unexpected unknown error: %+v", unknownErr)
	}
}

func TestRegistryRegisterRejectsDuplicate(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	if regErr := registry.Register(problem.Conflict()); regErr != nil {
		t.Fatalf("first register: %v", regErr)
	}
	if regErr := registry.Register(problem.Conflict()); regErr == nil {
		t.Fatal("expected duplicate register to fail")
	}
}

func TestRegistryTypeURIFor(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	uri, err := registry.TypeURIFor(problem.EntityNotFound())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found"
	if uri != want {
		t.Fatalf("TypeURIFor = %q, want %q", uri, want)
	}
}

func TestRegistryTypeURIForInvalidPortal(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(problem.ErrorPortal{})
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	if _, uriErr := registry.TypeURIFor(problem.Conflict()); uriErr == nil {
		t.Fatal("expected type URI error for empty portal")
	}
}

func TestGenericProblemsSetMatchesBaseline(t *testing.T) {
	t.Parallel()
	generics := problem.GenericProblems()
	wantIDs := []string{"validation-error", "entity-not-found", "conflict", "unauthenticated", "unauthorized", "invalid-json"}
	if len(generics) != len(wantIDs) {
		t.Fatalf("expected %d generics, got %d", len(wantIDs), len(generics))
	}
	for index, want := range wantIDs {
		if generics[index].ID != want {
			t.Fatalf("generic[%d] = %q, want %q", index, generics[index].ID, want)
		}
	}
}

func TestGenericProblemsFieldsAndSchemas(t *testing.T) {
	t.Parallel()
	cases := map[string]struct {
		build       func() problem.Type
		status      int
		recoverable bool
		hasSchema   bool
	}{
		"validation-error": {problem.ValidationError, 400, true, true},
		"entity-not-found": {problem.EntityNotFound, 404, false, true},
		"conflict":         {problem.Conflict, 409, true, true},
		"unauthenticated":  {problem.Unauthenticated, 401, true, false},
		"unauthorized":     {problem.Unauthorized, 403, false, false},
		"invalid-json":     {problem.InvalidJSON, 400, true, false},
	}
	for id, tc := range cases {
		built := tc.build()
		if built.ID != id || built.Version != "v1" {
			t.Fatalf("%s: unexpected id/version %+v", id, built)
		}
		if built.Status != tc.status || built.Recoverable != tc.recoverable {
			t.Fatalf("%s: status/recoverable %+v", id, built)
		}
		if tc.hasSchema && len(built.DataSchema) == 0 {
			t.Fatalf("%s: expected a data schema", id)
		}
		if !tc.hasSchema && len(built.DataSchema) != 0 {
			t.Fatalf("%s: expected no data schema, got %v", id, built.DataSchema)
		}
	}
}

func TestRegisterGenerics(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	if regErr := problem.RegisterGenerics(registry); regErr != nil {
		t.Fatalf("register generics: %v", regErr)
	}
	if len(registry.Entries()) != 6 {
		t.Fatalf("expected 6 registered generics, got %d", len(registry.Entries()))
	}
}

func TestRegisterGenericsRejectsConflict(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.Conflict())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	if regErr := problem.RegisterGenerics(registry); regErr == nil {
		t.Fatal("expected register-generics to fail on a pre-registered id")
	}
}
