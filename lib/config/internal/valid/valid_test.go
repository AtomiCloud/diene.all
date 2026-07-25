package valid_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/valid"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	tekuri "github.com/santhosh-tekuri/jsonschema/v6"
)

func objectSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"a": map[string]any{"type": "string"},
			"b": map[string]any{"type": "string"},
		},
		"required": []any{"a", "b"},
	}
}

func TestEvaluateAcceptsValid(t *testing.T) {
	t.Parallel()
	if err := valid.Evaluate(objectSchema(), problem.ErrorPortal{}, map[string]any{"a": "x", "b": "y"}); err != nil {
		t.Fatalf("valid instance must pass: %v", err)
	}
}

func TestEvaluateRejectsWithProblem(t *testing.T) {
	t.Parallel()
	err := valid.Evaluate(objectSchema(), problem.ErrorPortal{}, map[string]any{})
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		t.Fatalf("expected a problem error, got %v", err)
	}
	if problemErr.Problem.Status != 400 {
		t.Fatalf("expected 400, got %d", problemErr.Problem.Status)
	}
}

func TestEvaluateCompileFault(t *testing.T) {
	t.Parallel()
	err := valid.Evaluate(map[string]any{"x": make(chan int)}, problem.ErrorPortal{}, map[string]any{})
	if err == nil {
		t.Fatal("an unmarshalable schema must fault")
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) {
		t.Fatal("a compile fault is not a validation problem")
	}
}

func TestEvaluateNormalizeFault(t *testing.T) {
	t.Parallel()
	err := valid.Evaluate(objectSchema(), problem.ErrorPortal{}, map[string]any{"a": make(chan int)})
	if err == nil {
		t.Fatal("an unencodable instance must fault")
	}
}

func TestCompileRejectsUnmarshalableFragment(t *testing.T) {
	t.Parallel()
	if _, err := valid.Compile(map[string]any{"x": make(chan int)}); err == nil {
		t.Fatal("unmarshalable fragment must fail to compile")
	}
}

func TestNormalizeRejectsUnencodable(t *testing.T) {
	t.Parallel()
	if _, err := valid.Normalize(map[string]any{"a": make(chan int)}); err == nil {
		t.Fatal("unencodable instance must error")
	}
}

func TestCollectSingleAndNestedIssues(t *testing.T) {
	t.Parallel()
	compiled, err := valid.Compile(objectSchema())
	if err != nil {
		t.Fatalf("compile: %v", err)
	}
	// Two type mismatches on distinct properties produce a nested cause tree.
	var nested *tekuri.ValidationError
	if !errors.As(compiled.Validate(map[string]any{"a": 1, "b": 2}), &nested) {
		t.Fatal("expected a validation error")
	}
	if issues := valid.Collect(nested); len(issues) != 2 {
		t.Fatalf("nested collect must flatten every leaf: %v", issues)
	}
	// A single type mismatch produces a single leaf.
	var single *tekuri.ValidationError
	if !errors.As(compiled.Validate(map[string]any{"a": 1, "b": "y"}), &single) {
		t.Fatal("expected a validation error")
	}
	if issues := valid.Collect(single); len(issues) != 1 || issues[0].Path != "a" {
		t.Fatalf("single collect wrong: %v", issues)
	}
}

func TestAlignToSchemaRewritesKeysToSchemaSpelling(t *testing.T) {
	t.Parallel()
	schema := map[string]any{
		"properties": map[string]any{
			"cache_region": map[string]any{"type": "string"},
			"nested": map[string]any{
				"type":       "object",
				"properties": map[string]any{"inner_key": map[string]any{"type": "string"}},
			},
			"list": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type":       "object",
					"properties": map[string]any{"item_key": map[string]any{"type": "string"}},
				},
			},
			"scalars": map[string]any{"type": "array", "items": map[string]any{"type": "integer"}},
			"opaque":  map[string]any{"type": "object"},
		},
	}
	instance := map[string]any{
		"cacheRegion": "r",
		"nested":      map[string]any{"innerKey": "v"},
		"list":        []any{map[string]any{"itemKey": "x"}, "not-a-map"},
		"scalars":     []any{1, 2},
		"opaque":      map[string]any{"free-form": "kept"},
		"extra":       "kept",
		"orphanMap":   map[string]any{"a": 1},
	}
	aligned := valid.AlignToSchema(schema, instance)

	if aligned["cache_region"] != "r" {
		t.Fatalf("top-level key not aligned: %v", aligned)
	}
	nested, ok := aligned["nested"].(map[string]any)
	if !ok || nested["inner_key"] != "v" {
		t.Fatalf("nested key not aligned: %v", aligned["nested"])
	}
	list, ok := aligned["list"].([]any)
	if !ok || len(list) != 2 {
		t.Fatalf("list not preserved: %v", aligned["list"])
	}
	first, ok := list[0].(map[string]any)
	if !ok || first["item_key"] != "x" {
		t.Fatalf("array-of-object item key not aligned: %v", list[0])
	}
	if list[1] != "not-a-map" {
		t.Fatalf("non-object array element must be kept: %v", list[1])
	}
	if scalars, ok := aligned["scalars"].([]any); !ok || len(scalars) != 2 {
		t.Fatalf("scalar array with non-object items must be kept: %v", aligned["scalars"])
	}
	if aligned["extra"] != "kept" {
		t.Fatalf("unmatched scalar key must be kept: %v", aligned["extra"])
	}
	if orphan, ok := aligned["orphanMap"].(map[string]any); !ok || orphan["a"] != 1 {
		t.Fatalf("unmatched map key must be kept verbatim: %v", aligned["orphanMap"])
	}
	// A property whose schema has no nested properties recurses but aligns nothing.
	if opaque, ok := aligned["opaque"].(map[string]any); !ok || opaque["free-form"] != "kept" {
		t.Fatalf("properties-less object schema must keep its keys: %v", aligned["opaque"])
	}
}

func TestPathRootAndDotted(t *testing.T) {
	t.Parallel()
	if valid.Path(nil) != "(root)" {
		t.Fatalf("empty location must be root: %q", valid.Path(nil))
	}
	if valid.Path([]string{"app", "landscape"}) != "app.landscape" {
		t.Fatalf("dotted path wrong: %q", valid.Path([]string{"app", "landscape"}))
	}
}

func TestEnvIssueCoercionAndGeneric(t *testing.T) {
	t.Parallel()
	_, coercionErr := coreutils.EnvironmentToNestedMap(map[string]string{"P_X__0": "1", "P_X__2": "3"}, "P_")
	if coercionErr == nil {
		t.Fatal("expected a coercion error")
	}
	if issue := valid.EnvIssue(coercionErr); issue.Path == "(environment)" {
		t.Fatalf("coercion issue should carry the offending key, got %+v", issue)
	}
	if issue := valid.EnvIssue(errors.New("plain")); issue.Path != "(environment)" {
		t.Fatalf("generic issue should use the environment path, got %+v", issue)
	}
}

func TestProblemPortalVariants(t *testing.T) {
	t.Parallel()
	issues := []valid.Issue{{Path: "app.version", Message: "required"}}

	local := valid.Problem(problem.ErrorPortal{}, issues)
	if local.Problem.Type == "about:blank" {
		t.Fatal("a zero portal must fall back to the local portal, not about:blank")
	}

	configured := valid.Problem(problem.ErrorPortal{
		Scheme: "https", Host: "docs.example", Landscape: "raichu",
		Platform: "go", Service: "config", Module: "lib",
	}, issues)
	if configured.Problem.Status != 400 {
		t.Fatalf("expected 400, got %d", configured.Problem.Status)
	}

	invalid := valid.Problem(problem.ErrorPortal{
		Scheme: "https", Host: "docs.example", Landscape: "bad/seg",
		Platform: "go", Service: "config", Module: "lib",
	}, issues)
	if invalid.Problem.Type != "about:blank" {
		t.Fatalf("an invalid portal must fall back to about:blank, got %q", invalid.Problem.Type)
	}
}

func TestWireFormatsAcceptRejectAndSkip(t *testing.T) {
	t.Parallel()
	cases := map[string]struct{ valid, invalid string }{
		"wire-date":      {"2026-07-21", "2026-13-01"},
		"wire-time":      {"01:02:03", "24:00:00"},
		"iso-duration":   {"P1DT2H", "10 minutes"},
		"rfc3339-utc":    {"2026-07-21T01:02:03.000Z", "2026-07-21T01:02:03+08:00"},
		"iana-time-zone": {"Asia/Singapore", "asia/singapore"},
	}
	for _, format := range valid.WireFormats() {
		expectation, ok := cases[format.Name]
		if !ok {
			t.Fatalf("unexpected format %q", format.Name)
		}
		if err := format.Validate(expectation.valid); err != nil {
			t.Fatalf("%s must accept %q: %v", format.Name, expectation.valid, err)
		}
		if err := format.Validate(expectation.invalid); err == nil {
			t.Fatalf("%s must reject %q", format.Name, expectation.invalid)
		}
		if err := format.Validate(42); err != nil {
			t.Fatalf("%s must skip a non-string value: %v", format.Name, err)
		}
	}
}
