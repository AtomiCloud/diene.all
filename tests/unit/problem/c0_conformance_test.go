package problem_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// The authoritative shapes and samples live in tests/fixtures/c0/*.json
// (provenance in that dir's README). This suite LOADS them and validates the
// library against them; no authoritative value is hard-coded here.

func loadFixture(t *testing.T, name string) map[string]any {
	t.Helper()
	path := filepath.Join("..", "..", "fixtures", "c0", name)
	raw, err := os.ReadFile(path) //nolint:gosec // fixed in-repo fixture path
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	var parsed map[string]any
	if unmarshalErr := json.Unmarshal(raw, &parsed); unmarshalErr != nil {
		t.Fatalf("parse fixture %s: %v", name, unmarshalErr)
	}
	return parsed
}

func asMap(t *testing.T, value any) map[string]any {
	t.Helper()
	out, ok := value.(map[string]any)
	if !ok {
		t.Fatalf("expected a JSON object, got %T", value)
	}
	return out
}

func asSlice(t *testing.T, value any) []any {
	t.Helper()
	out, ok := value.([]any)
	if !ok {
		t.Fatalf("expected a JSON array, got %T", value)
	}
	return out
}

func asString(t *testing.T, value any) string {
	t.Helper()
	out, ok := value.(string)
	if !ok {
		t.Fatalf("expected a JSON string, got %T", value)
	}
	return out
}

func stringSlice(t *testing.T, value any) []string {
	t.Helper()
	items := asSlice(t, value)
	out := make([]string, 0, len(items))
	for _, item := range items {
		out = append(out, asString(t, item))
	}
	return out
}

func TestC0EnvelopeConformance(t *testing.T) {
	t.Parallel()
	fixture := loadFixture(t, "envelope.json")
	sample := asMap(t, fixture["sample"])

	expected := append(stringSlice(t, fixture["rfc9457Members"]), stringSlice(t, fixture["extensions"])...)
	for _, field := range expected {
		if _, ok := sample[field]; !ok {
			t.Fatalf("authoritative sample missing %q", field)
		}
	}

	encodedSample, err := json.Marshal(sample)
	if err != nil {
		t.Fatalf("marshal sample: %v", err)
	}
	var envelope problem.Problem
	if unmarshalErr := json.Unmarshal(encodedSample, &envelope); unmarshalErr != nil {
		t.Fatalf("Problem.UnmarshalJSON: %v", unmarshalErr)
	}
	roundTripped, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("Problem.MarshalJSON: %v", err)
	}
	var got map[string]any
	if unmarshalErr := json.Unmarshal(roundTripped, &got); unmarshalErr != nil {
		t.Fatalf("re-parse: %v", unmarshalErr)
	}
	if !reflect.DeepEqual(got, sample) {
		t.Fatalf("round-trip mismatch:\n got=%v\nwant=%v", got, sample)
	}
}

func TestC0CatalogEntryConformance(t *testing.T) {
	t.Parallel()
	fixture := loadFixture(t, "catalog-entry.json")
	required := stringSlice(t, fixture["requiredFields"])
	sample := asMap(t, fixture["sample"])

	for _, field := range required {
		if _, ok := sample[field]; !ok {
			t.Fatalf("authoritative sample missing %q", field)
		}
	}

	endpointsRaw := asSlice(t, sample["endpoints"])
	endpoints := make([]problem.CatalogEndpoint, 0, len(endpointsRaw))
	for _, item := range endpointsRaw {
		endpoint := asMap(t, item)
		endpoints = append(endpoints, problem.CatalogEndpoint{
			Method: asString(t, endpoint["method"]),
			Path:   asString(t, endpoint["path"]),
		})
	}
	status, ok := sample["status"].(float64)
	if !ok {
		t.Fatalf("status must be a number, got %T", sample["status"])
	}
	recoverable, ok := sample["recoverable"].(bool)
	if !ok {
		t.Fatalf("recoverable must be a bool, got %T", sample["recoverable"])
	}
	entry := problem.CatalogEntry{
		ID:          asString(t, sample["id"]),
		TypeURI:     asString(t, sample["type"]),
		Title:       asString(t, sample["title"]),
		Status:      int(status),
		Recoverable: recoverable,
		DataSchema:  asMap(t, sample["data"]),
		Endpoints:   endpoints,
	}
	crd := entry.ToCRDContent()
	for _, field := range required {
		if _, ok := crd[field]; !ok {
			t.Fatalf("emitter missing required field %q", field)
		}
	}
}

func TestC0TypeURIConformance(t *testing.T) {
	t.Parallel()
	fixture := loadFixture(t, "type-uri.json")
	segments := asMap(t, fixture["segments"])
	portal := problem.ErrorPortal{
		Scheme:    asString(t, segments["scheme"]),
		Host:      asString(t, segments["host"]),
		Landscape: asString(t, segments["landscape"]),
		Platform:  asString(t, segments["platform"]),
		Service:   asString(t, segments["service"]),
		Module:    asString(t, segments["module"]),
	}
	got, err := problem.TypeURI(portal, asString(t, segments["version"]), asString(t, segments["id"]))
	if err != nil {
		t.Fatalf("TypeURI: %v", err)
	}
	if got != asString(t, fixture["expectedTypeUri"]) {
		t.Fatalf("type URI = %q, want %q", got, fixture["expectedTypeUri"])
	}
	want := "{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}"
	if asString(t, fixture["template"]) != want {
		t.Fatalf("fixture template drifted from C0 §2: %q", fixture["template"])
	}
}
