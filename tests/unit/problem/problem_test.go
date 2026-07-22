package problem_test

import (
	"encoding/json"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestMarshalJSONOmitsEmptyDetailAndInstance(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "t", Title: "T", Status: 400, Recoverable: true}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out map[string]any
	if unmarshalErr := json.Unmarshal(encoded, &out); unmarshalErr != nil {
		t.Fatalf("unmarshal: %v", unmarshalErr)
	}
	for _, key := range []string{"type", "title", "status", "recoverable", "data"} {
		if _, ok := out[key]; !ok {
			t.Fatalf("missing key %q in %v", key, out)
		}
	}
	if _, ok := out["detail"]; ok {
		t.Fatalf("empty detail should be omitted: %v", out)
	}
	if _, ok := out["instance"]; ok {
		t.Fatalf("empty instance should be omitted: %v", out)
	}
	data, ok := out["data"].(map[string]any)
	if !ok || len(data) != 0 {
		t.Fatalf("data should render as an empty object, got %v", out["data"])
	}
}

func TestMarshalJSONIncludesDetailInstanceAndData(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{
		Type:     "t",
		Title:    "T",
		Status:   404,
		Detail:   new("missing"),
		Instance: new("/x"),
		Data:     map[string]any{"resource": "user"},
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out map[string]any
	if unmarshalErr := json.Unmarshal(encoded, &out); unmarshalErr != nil {
		t.Fatalf("unmarshal: %v", unmarshalErr)
	}
	if out["detail"] != "missing" || out["instance"] != "/x" {
		t.Fatalf("detail/instance not preserved: %v", out)
	}
}

func TestMarshalJSONFailsOnUnmarshalableData(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "t", Title: "T", Status: 500, Data: map[string]any{"fn": func() {}}}
	if _, err := json.Marshal(envelope); err == nil {
		t.Fatal("expected marshal error for func in data")
	}
}

func TestUnmarshalJSONRoundTrip(t *testing.T) {
	t.Parallel()
	source := []byte(`{"type":"t","title":"T","status":404,"detail":"d","instance":"/i","recoverable":true,"data":{"k":"v"}}`)
	var envelope problem.Problem
	if err := json.Unmarshal(source, &envelope); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if envelope.Type != "t" || envelope.Title != "T" || envelope.Status != 404 {
		t.Fatalf("core members wrong: %+v", envelope)
	}
	if envelope.Detail == nil || *envelope.Detail != "d" ||
		envelope.Instance == nil || *envelope.Instance != "/i" || !envelope.Recoverable {
		t.Fatalf("optional members wrong: %+v", envelope)
	}
	if envelope.Data["k"] != "v" {
		t.Fatalf("data wrong: %+v", envelope.Data)
	}
}

func TestUnmarshalJSONAppliesDefaults(t *testing.T) {
	t.Parallel()
	var envelope problem.Problem
	if err := json.Unmarshal([]byte(`{}`), &envelope); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if envelope.Type != "about:blank" {
		t.Fatalf("type default wrong: %q", envelope.Type)
	}
	if envelope.Title != "Unexpected problem" {
		t.Fatalf("title default wrong: %q", envelope.Title)
	}
	if envelope.Status != 500 {
		t.Fatalf("status default wrong: %d", envelope.Status)
	}
	if envelope.Detail != nil || envelope.Instance != nil || envelope.Recoverable {
		t.Fatalf("optional defaults wrong: %+v", envelope)
	}
	if envelope.Data == nil || len(envelope.Data) != 0 {
		t.Fatalf("data default should be empty map: %+v", envelope.Data)
	}
}

func TestUnmarshalJSONIgnoresWrongTypedMembers(t *testing.T) {
	t.Parallel()
	var envelope problem.Problem
	source := []byte(`{"type":5,"status":"nope","recoverable":"nope","data":"nope"}`)
	if err := json.Unmarshal(source, &envelope); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if envelope.Type != "about:blank" || envelope.Status != 500 || envelope.Recoverable {
		t.Fatalf("wrong-typed members should fall back to defaults: %+v", envelope)
	}
	if len(envelope.Data) != 0 {
		t.Fatalf("wrong-typed data should fall back to empty: %+v", envelope.Data)
	}
}

func TestUnmarshalJSONRejectsInvalidJSON(t *testing.T) {
	t.Parallel()
	var envelope problem.Problem
	if err := envelope.UnmarshalJSON([]byte(`{`)); err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestEqual(t *testing.T) {
	t.Parallel()
	base := problem.Problem{Type: "t", Title: "T", Status: 404, Data: map[string]any{"id": 42}}
	same := problem.Problem{Type: "t", Title: "T", Status: 404, Data: map[string]any{"id": 42}}
	other := problem.Problem{Type: "t", Title: "T", Status: 409, Data: map[string]any{"id": 42}}
	if !base.Equal(same) {
		t.Fatal("expected equal problems to compare equal")
	}
	if base.Equal(other) {
		t.Fatal("expected differing problems to compare unequal")
	}
}

func TestEqualFalseWhenUnmarshalable(t *testing.T) {
	t.Parallel()
	bad := problem.Problem{Type: "t", Title: "T", Status: 500, Data: map[string]any{"fn": func() {}}}
	good := problem.Problem{Type: "t", Title: "T", Status: 500}
	if bad.Equal(good) {
		t.Fatal("unmarshalable problem must never compare equal")
	}
}

func TestString(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "https://x/v1/entity-not-found", Title: "Entity not found", Status: 404}
	got := envelope.String()
	want := "Problem(https://x/v1/entity-not-found, 404, Entity not found)"
	if got != want {
		t.Fatalf("String() = %q, want %q", got, want)
	}
}

// TestUnmarshalMarshalPreservesExplicitEmptyDetailInstance is the Blocker-1
// regression: an envelope carrying explicit empty `detail`/`instance` survives
// an unmarshal→marshal cycle byte-identically (the keys are retained as ""),
// matching the Dart sibling's nullable-field wire behavior (present-empty is
// distinct from absent).
func TestUnmarshalMarshalPreservesExplicitEmptyDetailInstance(t *testing.T) {
	t.Parallel()
	source := []byte(
		`{"data":{},"detail":"","instance":"","recoverable":false,"status":400,"title":"T","type":"t"}`,
	)
	var envelope problem.Problem
	if err := json.Unmarshal(source, &envelope); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if envelope.Detail == nil || *envelope.Detail != "" {
		t.Fatalf("explicit empty detail should be present-empty, got %v", envelope.Detail)
	}
	if envelope.Instance == nil || *envelope.Instance != "" {
		t.Fatalf("explicit empty instance should be present-empty, got %v", envelope.Instance)
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(encoded) != string(source) {
		t.Fatalf("round-trip not byte-identical:\n got=%s\nwant=%s", encoded, source)
	}
}

// TestUnmarshalMarshalDoesNotInventDetailInstance is the Blocker-1 regression
// for the absent case: an envelope WITHOUT `detail`/`instance` must not gain
// those keys after an unmarshal→marshal cycle.
func TestUnmarshalMarshalDoesNotInventDetailInstance(t *testing.T) {
	t.Parallel()
	source := []byte(`{"data":{},"recoverable":false,"status":400,"title":"T","type":"t"}`)
	var envelope problem.Problem
	if err := json.Unmarshal(source, &envelope); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if envelope.Detail != nil || envelope.Instance != nil {
		t.Fatalf("absent members should stay nil, got detail=%v instance=%v", envelope.Detail, envelope.Instance)
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(encoded) != string(source) {
		t.Fatalf("absent keys must not be invented:\n got=%s\nwant=%s", encoded, source)
	}
}
