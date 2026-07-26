package standardconfig_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// asProblem is errors.As specialised to the problem error type, so the suite
// reads as intent rather than as pointer plumbing.
func asProblem(err error, target **problem.Error) bool {
	return errors.As(err, target)
}

func TestProblemTypesAreStableAndVersioned(t *testing.T) {
	declared := standardconfig.ProblemTypes()
	if len(declared) != 4 {
		t.Fatalf("ProblemTypes() length = %d, want 4", len(declared))
	}
	wantIDs := []string{
		standardconfig.ProblemConnectionUnknown,
		standardconfig.ProblemConnectionAmbiguous,
		standardconfig.ProblemConnectionKeyInvalid,
		standardconfig.ProblemPresetUnknown,
	}
	for index, want := range wantIDs {
		if declared[index].ID != want {
			t.Fatalf("ProblemTypes()[%d].ID = %q, want %q", index, declared[index].ID, want)
		}
		if declared[index].Version != standardconfig.ProblemVersion {
			t.Fatalf("%s version = %q, want %q", want, declared[index].Version, standardconfig.ProblemVersion)
		}
		if declared[index].Status != 500 {
			t.Fatalf("%s status = %d, want 500", want, declared[index].Status)
		}
		if declared[index].Recoverable {
			t.Fatalf("%s is recoverable; a misconfiguration is never retryable", want)
		}
		if declared[index].Title == "" {
			t.Fatalf("%s has no title", want)
		}
	}
}

func TestNewProblemsAcceptsConsumerTypes(t *testing.T) {
	problems, err := standardconfig.NewProblems(portal(), problem.Type{
		ID: "tenant-suspended", Title: "Tenant suspended", Version: "v1", Status: 403,
	})
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	if _, found := problems.Registry().Lookup("tenant-suspended"); !found {
		t.Fatalf("%s", "consumer type was not registered alongside the shipped ones")
	}
	if len(problems.Registry().Entries()) != 5 {
		t.Fatalf("registry size = %d, want 5", len(problems.Registry().Entries()))
	}
}

func TestNewProblemsRejectsAnIDThatShadowsAShippedProblem(t *testing.T) {
	problems, err := standardconfig.NewProblems(portal(), problem.Type{
		ID: standardconfig.ProblemPresetUnknown, Title: "Mine now", Version: "v1", Status: 400,
	})
	if err == nil {
		t.Fatalf("NewProblems() accepted a colliding id, registry = %v", problems)
	}
	if problems != nil {
		t.Fatalf("NewProblems() returned %v alongside an error", problems)
	}
}

func TestRaiseMintsTheSingleSourceTypeURI(t *testing.T) {
	err := newProblems(t, portal()).Raise(
		standardconfig.ProblemConnectionKeyInvalid, "lowercase pool", map[string]any{"block": "kv"},
	)
	raised := requireProblem(t, err)
	want := "https://docs.atomi.cloud/docs/lapras/sulfoxide/billing/core/v1/connection-key-invalid"
	if raised.Type != want {
		t.Fatalf("Raise() type = %q, want %q", raised.Type, want)
	}
	if raised.Status != 500 {
		t.Fatalf("Raise() status = %d, want 500", raised.Status)
	}
	if raised.Detail == nil || *raised.Detail != "lowercase pool" {
		t.Fatalf("Raise() detail = %v, want %q", raised.Detail, "lowercase pool")
	}
	if raised.Data["block"] != "kv" {
		t.Fatalf("Raise() data = %v, want the supplied payload", raised.Data)
	}
}

func TestRaiseDefaultsANilDataPayloadToAnEmptyMap(t *testing.T) {
	raised := requireProblem(t, newProblems(t, portal()).Raise(
		standardconfig.ProblemPresetUnknown, "no such preset", nil,
	))
	if raised.Data == nil {
		t.Fatalf("%s", "Raise() left data nil; the wire form must carry an object")
	}
	if len(raised.Data) != 0 {
		t.Fatalf("Raise() data = %v, want empty", raised.Data)
	}
}

func TestRaiseFallsBackWhenTheIDIsNotRegistered(t *testing.T) {
	raised := requireProblem(t, newProblems(t, portal()).Raise(
		"never-declared", "describing an undeclared failure", map[string]any{"seen": true},
	))
	if raised.Status != 500 {
		t.Fatalf("uncatalogued status = %d, want 500", raised.Status)
	}
	if raised.Detail == nil || *raised.Detail != "describing an undeclared failure" {
		t.Fatalf("uncatalogued lost the detail: %v", raised.Detail)
	}
	if seen, ok := raised.Data["seen"].(bool); !ok || !seen {
		t.Fatalf("uncatalogued lost the data payload: %v", raised.Data)
	}
}

func TestRaiseFallsBackWhenTheTypeURICannotBeBuilt(t *testing.T) {
	raised := requireProblem(t, newProblems(t, brokenPortal()).Raise(
		standardconfig.ProblemConnectionUnknown, "portal is incomplete", nil,
	))
	if raised.Status != 500 {
		t.Fatalf("uncatalogued status = %d, want 500", raised.Status)
	}
	if raised.Detail == nil || *raised.Detail != "portal is incomplete" {
		t.Fatalf("uncatalogued lost the detail: %v", raised.Detail)
	}
}

func TestCatalogRendersEveryShippedType(t *testing.T) {
	catalog, err := newProblems(t, portal()).Catalog()
	if err != nil {
		t.Fatalf("Catalog() error = %v", err)
	}
	content := catalog.ToCRDContent()
	if len(content) != len(standardconfig.ProblemTypes()) {
		t.Fatalf("catalog size = %d, want %d", len(content), len(standardconfig.ProblemTypes()))
	}
	if _, found := catalog.Lookup(standardconfig.ProblemConnectionUnknown); !found {
		t.Fatalf("%s", "catalog is missing the connection-unknown entry")
	}
}

func TestCatalogSurfacesAnUnbuildableTypeURI(t *testing.T) {
	catalog, err := newProblems(t, brokenPortal()).Catalog()
	if err == nil {
		t.Fatalf("Catalog() built %v from an incomplete portal", catalog)
	}
	if catalog != nil {
		t.Fatalf("Catalog() returned %v alongside an error", catalog)
	}
}

func TestRegistryExposesTheShippedDeclarations(t *testing.T) {
	registry := newProblems(t, portal()).Registry()
	if registry.Portal() != portal() {
		t.Fatalf("Registry().Portal() = %v, want %v", registry.Portal(), portal())
	}
	declared, found := registry.Lookup(standardconfig.ProblemConnectionKeyInvalid)
	if !found {
		t.Fatalf("%s", "registry is missing the connection-key-invalid declaration")
	}
	if declared.Title != "Connection name is not an identifier" {
		t.Fatalf("declaration title = %q", declared.Title)
	}
}
