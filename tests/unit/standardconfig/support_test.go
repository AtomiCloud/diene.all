package standardconfig_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

// portal is the well-formed service-tree error portal the suite mints type URIs
// from.
func portal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.atomi.cloud",
		Landscape: "lapras",
		Platform:  "sulfoxide",
		Service:   "billing",
		Module:    "core",
	}
}

// brokenPortal carries a blank LPSM segment, so every type URI minted from it
// fails to build. It is how the suite reaches the uncatalogued fallback without
// mutating a registry.
func brokenPortal() problem.ErrorPortal {
	broken := portal()
	broken.Module = ""
	return broken
}

// newProblems builds the factory under test, failing the test rather than
// returning an error the caller has to re-check.
func newProblems(t *testing.T, using problem.ErrorPortal) *standardconfig.Problems {
	t.Helper()
	problems, err := standardconfig.NewProblems(using)
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	return problems
}

// entrySchema unwraps a preset fragment's entry schema.
func entrySchema(t *testing.T, preset map[string]any) map[string]any {
	t.Helper()
	entry, ok := preset["additionalProperties"].(map[string]any)
	if !ok {
		t.Fatalf("preset fragment has no entry schema: %v", preset)
	}
	return entry
}

// entryProperties unwraps a preset fragment's entry property map.
func entryProperties(t *testing.T, preset map[string]any) map[string]any {
	t.Helper()
	properties, ok := entrySchema(t, preset)["properties"].(map[string]any)
	if !ok {
		t.Fatalf("preset entry schema has no properties: %v", preset)
	}
	return properties
}

// requireProblem fails unless err carries a problem-typed error, and returns
// its envelope.
func requireProblem(t *testing.T, err error) problem.Problem {
	t.Helper()
	var raised *problem.Error
	if !asProblem(err, &raised) {
		t.Fatalf("expected a problem-typed error, got %v", err)
	}
	return raised.Problem
}

// objectAt unwraps a nested object out of a JSON Schema fragment.
func objectAt(t *testing.T, source map[string]any, key string) map[string]any {
	t.Helper()
	nested, ok := source[key].(map[string]any)
	if !ok {
		t.Fatalf("no object schema at %q in %v", key, source)
	}
	return nested
}

// descriptionOf unwraps the human-readable annotation off a JSON Schema
// fragment. Descriptions are asserted because a preset block whose contract is
// undocumented is a preset a service will wire up wrongly.
func descriptionOf(t *testing.T, source map[string]any) string {
	t.Helper()
	value, ok := source["description"].(string)
	if !ok {
		t.Fatalf("no description in %v", source)
	}
	return value
}
