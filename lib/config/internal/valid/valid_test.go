package valid_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/resource"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/valid"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	tekuri "github.com/santhosh-tekuri/jsonschema/v6"
)

func objectSchema() map[string]any {
	return map[string]any{
		"$schema": schemaview.Dialect,
		"type":    "object",
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

func TestEvaluateSchemaNormalizeFault(t *testing.T) {
	t.Parallel()
	err := valid.Evaluate(map[string]any{"x": make(chan int)}, problem.ErrorPortal{}, map[string]any{})
	if err == nil {
		t.Fatal("an unmarshalable schema must fault")
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) {
		t.Fatal("a schema normalize fault is not a validation problem")
	}
}

func TestEvaluateCompileFault(t *testing.T) {
	t.Parallel()
	// This schema normalizes cleanly and passes the supported-subset audit, but
	// violates the draft-2020-12 metaschema, so the fault surfaces from
	// compilation rather than from normalization or the audit.
	err := valid.Evaluate(
		map[string]any{"$schema": schemaview.Dialect, "type": float64(5)},
		problem.ErrorPortal{},
		map[string]any{},
	)
	if err == nil {
		t.Fatal("a schema that violates the metaschema must fault")
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

func TestEvaluateRejectsNormalizedInstanceCollision(t *testing.T) {
	t.Parallel()
	// A typed container flattened during normalization still carries case-only
	// aliases; the collision check runs on the normalized object and fails closed.
	instance := map[string]any{"a": "x", "b": "y", "svc": map[string]string{"cache-region": "1", "cacheRegion": "2"}}
	err := valid.Evaluate(objectSchema(), problem.ErrorPortal{}, instance)
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		t.Fatalf("a normalized-instance collision must be a validation problem: %v", err)
	}
}

func TestEvaluateRejectsCyclicSchema(t *testing.T) {
	t.Parallel()
	// The clone package now preserves caller cycles, so a cyclic schema fragment
	// must fault at the marshal gate rather than hang the property/alignment walks.
	cyclic := map[string]any{"type": "object"}
	cyclic["self"] = cyclic
	err := valid.Evaluate(cyclic, problem.ErrorPortal{}, map[string]any{})
	if err == nil {
		t.Fatal("a cyclic schema must fault, not hang")
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) {
		t.Fatal("a cyclic authoring fault is a plain error, not a validation problem")
	}
}

func TestEvaluateRejectsCollidingSchema(t *testing.T) {
	t.Parallel()
	schema := map[string]any{
		"$schema":    schemaview.Dialect,
		"type":       "object",
		"properties": map[string]any{"cache_region": map[string]any{"type": "string"}, "cacheRegion": map[string]any{"type": "string"}},
	}
	err := valid.Evaluate(schema, problem.ErrorPortal{}, map[string]any{})
	if err == nil {
		t.Fatal("a schema with canonical-duplicate properties must be rejected")
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) {
		t.Fatal("a schema authoring fault is a plain error, not a validation problem")
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
	if issues := valid.Collect(single); len(issues) != 1 || issues[0].Locate() != "a" {
		t.Fatalf("single collect wrong: %v", issues)
	}
}

func TestEvaluateRejectsTypedPropertiesCollision(t *testing.T) {
	t.Parallel()
	// A legal NewBlock fragment may use typed authoring containers. Before the
	// schema was normalized, the direct map[string]any assertion skipped this
	// shape entirely and the collision went undetected.
	schema := map[string]any{
		"$schema": schemaview.Dialect,
		"type":    "object",
		"properties": map[string]map[string]any{
			"cache_region": {"type": "string"},
			"cacheRegion":  {"type": "string"},
		},
	}
	err := valid.Evaluate(schema, problem.ErrorPortal{}, map[string]any{})
	if err == nil {
		t.Fatal("a typed-container canonical collision must be rejected")
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) {
		t.Fatal("a schema authoring fault is a plain error, not a validation problem")
	}
}

func TestEvaluateValidatesThroughBlockLocalRef(t *testing.T) {
	t.Parallel()
	// The composed shape a block mount produces: the block is its own resource, so
	// its fragment-local pointer resolves inside the block. The instance spells the
	// key in camel case while the schema declares it in snake case behind
	// $defs + $ref with additionalProperties:false, so it only validates because
	// both sides are canonicalized.
	schema := map[string]any{
		"$schema": schemaview.Dialect,
		"type":    "object",
		"properties": map[string]any{
			"app": map[string]any{
				"$id": resource.BlockID("app"),
				"$defs": map[string]any{"body": map[string]any{
					"type":                 "object",
					"properties":           map[string]any{"cache_region": map[string]any{"type": "string"}},
					"additionalProperties": false,
				}},
				"$ref": "#/$defs/body",
			},
		},
	}
	instance := map[string]any{"app": map[string]any{"cacheRegion": "east"}}
	if err := valid.Evaluate(schema, problem.ErrorPortal{}, instance); err != nil {
		t.Fatalf("a block-local reference must validate: %v", err)
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
