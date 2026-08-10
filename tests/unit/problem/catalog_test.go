package problem_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestCatalogEndpointToContent(t *testing.T) {
	t.Parallel()
	content := problem.CatalogEndpoint{Method: "POST", Path: "/user"}.ToContent()
	if content["method"] != "POST" || content["path"] != "/user" {
		t.Fatalf("unexpected endpoint content: %v", content)
	}
}

func TestCatalogEntryToCRDContentWithEndpoints(t *testing.T) {
	t.Parallel()
	entry := problem.CatalogEntry{
		ID:          "validation-error",
		TypeURI:     "https://x/v1/validation-error",
		Title:       "Validation error",
		Status:      400,
		Recoverable: true,
		DataSchema:  map[string]any{"type": "object"},
		Endpoints:   []problem.CatalogEndpoint{{Method: "POST", Path: "/user"}},
	}
	crd := entry.ToCRDContent()
	for _, key := range []string{"id", "type", "title", "status", "recoverable", "data", "endpoints"} {
		if _, ok := crd[key]; !ok {
			t.Fatalf("missing key %q in %v", key, crd)
		}
	}
	endpoints, ok := crd["endpoints"].([]map[string]any)
	if !ok || len(endpoints) != 1 || endpoints[0]["method"] != "POST" {
		t.Fatalf("endpoints not rendered: %v", crd["endpoints"])
	}
}

func TestCatalogEntryToCRDContentDefaultsEmptyDataAndEndpoints(t *testing.T) {
	t.Parallel()
	crd := problem.CatalogEntry{ID: "x", TypeURI: "t", Title: "X", Status: 500}.ToCRDContent()
	data, ok := crd["data"].(map[string]any)
	if !ok || len(data) != 0 {
		t.Fatalf("data should default to empty object: %v", crd["data"])
	}
	endpoints, ok := crd["endpoints"].([]map[string]any)
	if !ok || len(endpoints) != 0 {
		t.Fatalf("endpoints should default to empty list: %v", crd["endpoints"])
	}
}

func TestNewCatalogPrepopulatesAndPortal(t *testing.T) {
	t.Parallel()
	entry := problem.CatalogEntry{ID: "x", TypeURI: "t", Title: "X", Status: 500}
	catalog := problem.NewCatalog(testPortal(), entry)
	if len(catalog.Entries()) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(catalog.Entries()))
	}
	if catalog.Portal() != testPortal() {
		t.Fatalf("portal not preserved: %+v", catalog.Portal())
	}
}

func TestCatalogAddReplacesKeepingPosition(t *testing.T) {
	t.Parallel()
	catalog := problem.NewCatalog(testPortal())
	catalog.Add(problem.CatalogEntry{ID: "a", Title: "first"})
	catalog.Add(problem.CatalogEntry{ID: "b", Title: "second"})
	catalog.Add(problem.CatalogEntry{ID: "a", Title: "replaced"})
	entries := catalog.Entries()
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries after replace, got %d", len(entries))
	}
	if entries[0].ID != "a" || entries[0].Title != "replaced" {
		t.Fatalf("replace should keep position and update value: %+v", entries[0])
	}
}

func TestCatalogAddType(t *testing.T) {
	t.Parallel()
	catalog := problem.NewCatalog(testPortal())
	if err := catalog.AddType(problem.EntityNotFound(), problem.CatalogEndpoint{Method: "GET", Path: "/user/42"}); err != nil {
		t.Fatalf("add type: %v", err)
	}
	entry, ok := catalog.Lookup("entity-not-found")
	if !ok {
		t.Fatal("expected entity-not-found entry")
	}
	if entry.Status != 404 || len(entry.Endpoints) != 1 {
		t.Fatalf("unexpected entry: %+v", entry)
	}
	want := "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found"
	if entry.TypeURI != want {
		t.Fatalf("type URI = %q, want %q", entry.TypeURI, want)
	}
}

func TestCatalogAddTypeAppliesDefaultStatus(t *testing.T) {
	t.Parallel()
	catalog := problem.NewCatalog(testPortal())
	if err := catalog.AddType(problem.Type{ID: "custom", Title: "Custom", Version: "v1"}); err != nil {
		t.Fatalf("add type: %v", err)
	}
	entry, _ := catalog.Lookup("custom")
	if entry.Status != 500 {
		t.Fatalf("expected default status 500, got %d", entry.Status)
	}
	if entry.Endpoints == nil || len(entry.Endpoints) != 0 {
		t.Fatalf("expected empty endpoints slice, got %v", entry.Endpoints)
	}
}

func TestCatalogAddTypeRejectsInvalidPortal(t *testing.T) {
	t.Parallel()
	catalog := problem.NewCatalog(problem.ErrorPortal{})
	if err := catalog.AddType(problem.Conflict()); err == nil {
		t.Fatal("expected error for empty portal")
	}
}

func TestCatalogAddGenerics(t *testing.T) {
	t.Parallel()
	catalog := problem.NewCatalog(testPortal())
	if err := catalog.AddGenerics(); err != nil {
		t.Fatalf("add generics: %v", err)
	}
	content := catalog.ToCRDContent()
	if len(content) != 6 {
		t.Fatalf("expected 6 rows, got %d", len(content))
	}
	if content[0]["id"] != "validation-error" {
		t.Fatalf("unexpected first row: %v", content[0])
	}
}

func TestCatalogAddGenericsRejectsInvalidPortal(t *testing.T) {
	t.Parallel()
	catalog := problem.NewCatalog(problem.ErrorPortal{})
	if err := catalog.AddGenerics(); err == nil {
		t.Fatal("expected error for empty portal")
	}
}

func TestCatalogLookupMissing(t *testing.T) {
	t.Parallel()
	catalog := problem.NewCatalog(testPortal())
	if _, ok := catalog.Lookup("missing"); ok {
		t.Fatal("expected missing lookup to report absent")
	}
}
