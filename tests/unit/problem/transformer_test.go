package problem_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestDefaultTransformOptions(t *testing.T) {
	t.Parallel()
	options := problem.DefaultTransformOptions()
	if options.DefaultStatus != 500 || options.DefaultVersion != "v1" {
		t.Fatalf("unexpected defaults: %+v", options)
	}
	if options.Portal != problem.LocalErrorPortal() {
		t.Fatalf("expected local portal, got %+v", options.Portal)
	}
	if options.Registry != nil {
		t.Fatal("expected nil registry by default")
	}
}

func TestFromObjectPassesThroughProblem(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "t", Title: "T", Status: 404}
	if got := problem.FromObject(envelope, problem.DefaultTransformOptions()); !got.Equal(envelope) {
		t.Fatalf("expected passthrough, got %+v", got)
	}
}

func TestFromObjectRecoversError(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "t", Title: "T", Status: 409}
	err := problem.NewError(envelope)
	if got := problem.FromObject(err, problem.DefaultTransformOptions()); !got.Equal(envelope) {
		t.Fatalf("expected recovered problem, got %+v", got)
	}
}

func TestFromObjectRegistryKnownID(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.EntityNotFound())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	value := map[string]any{"problemId": "entity-not-found", "data": map[string]any{"resource": "user"}}
	got := problem.FromObject(value, options)
	if got.Status != 404 || got.Title != "Entity not found" {
		t.Fatalf("expected registry-resolved problem, got %+v", got)
	}
	if got.Data["resource"] != "user" {
		t.Fatalf("expected preserved data, got %+v", got.Data)
	}
	want := "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found"
	if got.Type != want {
		t.Fatalf("type = %q, want %q", got.Type, want)
	}
}

func TestFromObjectRegistryDefaultStatusWhenTypeHasNone(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.Type{ID: "custom", Title: "Custom", Version: "v1"})
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	got := problem.FromObject(map[string]any{"problemId": "custom"}, options)
	if got.Status != 500 {
		t.Fatalf("expected default status 500, got %d", got.Status)
	}
}

func TestFromObjectRegistryInvalidPortalFallsBackToBlank(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(problem.ErrorPortal{}, problem.Conflict())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	got := problem.FromObject(map[string]any{"problemId": "conflict"}, options)
	if got.Type != "about:blank" {
		t.Fatalf("expected about:blank fallback, got %q", got.Type)
	}
}

func TestFromObjectUnknownIDFallsThroughToUncatalogued(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.Conflict())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	got := problem.FromObject(map[string]any{"problemId": "nope"}, options)
	if got.Title != "Unexpected problem" {
		t.Fatalf("expected uncatalogued fallback, got %+v", got)
	}
}

func TestFromObjectUncataloguedForPlainError(t *testing.T) {
	t.Parallel()
	got := problem.FromObject(errors.New("boom"), problem.DefaultTransformOptions())
	if got.Title != "Unexpected problem" || got.Status != 500 {
		t.Fatalf("unexpected uncatalogued problem: %+v", got)
	}
	if got.Detail != "boom" {
		t.Fatalf("expected detail from error, got %q", got.Detail)
	}
	if got.Type == "" || got.Type == "about:blank" {
		t.Fatalf("expected a built uncatalogued type URI, got %q", got.Type)
	}
}

func TestFromObjectUncataloguedInvalidPortalFallsBackToBlank(t *testing.T) {
	t.Parallel()
	options := problem.TransformOptions{DefaultStatus: 500, DefaultVersion: "v1"}
	got := problem.FromObject("bare string", options)
	if got.Type != "about:blank" {
		t.Fatalf("expected about:blank fallback, got %q", got.Type)
	}
	if got.Detail != "bare string" {
		t.Fatalf("expected string detail, got %q", got.Detail)
	}
}

func TestFromObjectDetailVariants(t *testing.T) {
	t.Parallel()
	options := problem.DefaultTransformOptions()
	if got := problem.FromObject(nil, options); got.Detail != "" {
		t.Fatalf("nil detail should be empty, got %q", got.Detail)
	}
	if got := problem.FromObject(42, options); got.Detail != "42" {
		t.Fatalf("int detail should be %q, got %q", "42", got.Detail)
	}
}

func TestFromObjectRegistryIgnoresNonStringProblemID(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.Conflict())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	got := problem.FromObject(map[string]any{"problemId": 5}, options)
	if got.Title != "Unexpected problem" {
		t.Fatalf("non-string problemId should fall through, got %+v", got)
	}
}

func TestFromObjectRegistryIgnoresNonMapDataAndValues(t *testing.T) {
	t.Parallel()
	registry, err := problem.NewRegistry(testPortal(), problem.EntityNotFound())
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	got := problem.FromObject(map[string]any{"problemId": "entity-not-found", "data": "not-a-map"}, options)
	if len(got.Data) != 0 {
		t.Fatalf("non-map data should yield empty data, got %+v", got.Data)
	}
}
