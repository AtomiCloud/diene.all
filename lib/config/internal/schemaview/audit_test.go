package schemaview_test

import (
	"maps"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/resource"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
)

// compose builds the shape ComposeSchema produces: a dialect-bearing root with
// one block mounted as its own resource.
func compose(fragment map[string]any) map[string]any {
	mount := map[string]any{}
	maps.Copy(mount, fragment)
	if _, authored := mount["$id"]; !authored {
		mount["$id"] = resource.BlockID("demo")
	}
	return map[string]any{
		"$schema":    schemaview.Dialect,
		"type":       "object",
		"properties": map[string]any{"demo": mount},
	}
}

// normalize round-trips a schema into the generic tree the audit walks.
func normalize(t *testing.T, schema map[string]any) map[string]any {
	t.Helper()
	normalized, err := schemaview.Normalize(schema)
	if err != nil {
		t.Fatalf("normalize: %v", err)
	}
	return normalized
}

func TestDialectMatchesThePublicConstant(t *testing.T) {
	t.Parallel()
	// The internal packages cannot import the public one, so this is what keeps
	// the two spellings of the dialect from drifting apart.
	if schemaview.Dialect != config.Draft2020 {
		t.Fatalf("dialect drift: %q vs %q", schemaview.Dialect, config.Draft2020)
	}
}

func TestAuditRequiresTheRootDialect(t *testing.T) {
	t.Parallel()
	for _, root := range []map[string]any{
		{"type": "object"},
		{"$schema": "https://json-schema.org/draft-07/schema#", "type": "object"},
		{"$schema": float64(1), "type": "object"},
	} {
		if err := schemaview.Audit(normalize(t, root)); err == nil {
			t.Fatalf("root %v must be rejected without the exact dialect", root)
		}
	}
	if err := schemaview.Audit(normalize(t, compose(map[string]any{"type": "object"}))); err != nil {
		t.Fatalf("a composed root must be accepted: %v", err)
	}
}

func TestAuditDeniesEveryUnsupportedKeyword(t *testing.T) {
	t.Parallel()
	for keyword := range schemaview.DeniedKeywords() {
		t.Run(keyword, func(t *testing.T) {
			t.Parallel()
			err := schemaview.Audit(normalize(t, compose(map[string]any{"type": "object", keyword: true})))
			if err == nil {
				t.Fatalf("%q must be denied at a schema node", keyword)
			}
			if !strings.Contains(err.Error(), keyword) {
				t.Fatalf("the error must name the offending keyword: %v", err)
			}
		})
	}
}

func TestAuditDeniesKeywordsInsideNestedSchemaNodes(t *testing.T) {
	t.Parallel()
	nested := compose(map[string]any{
		"type": "object",
		"properties": map[string]any{"inner": map[string]any{
			"not": map[string]any{"propertyNames": map[string]any{"minLength": float64(2)}},
		}},
	})
	if err := schemaview.Audit(normalize(t, nested)); err == nil {
		t.Fatal("a denied keyword nested inside applicators must still be found")
	}
}

func TestAuditLeavesOpaqueDataAlone(t *testing.T) {
	t.Parallel()
	lookalike := map[string]any{
		"$ref": "https://example.invalid/x.json", "$id": "https://example.invalid/y.json",
		"$anchor": "a", "$dynamicRef": "#n", "$recursiveRef": "#",
		"patternProperties": map[string]any{"^x": true},
		"propertyNames":     map[string]any{"minLength": float64(2)},
		"dependencies":      map[string]any{"a": []any{"b"}},
		"contentSchema":     map[string]any{"type": "object"},
		"$schema":           "https://example.invalid/meta",
	}
	opaque := compose(map[string]any{
		"type": "object",
		"properties": map[string]any{
			"pinned": map[string]any{"const": lookalike},
			"choice": map[string]any{"enum": []any{lookalike, []any{lookalike}}},
			"noted":  map[string]any{"default": lookalike, "examples": []any{lookalike}},
		},
		"x-vendor": lookalike,
	})
	if err := schemaview.Audit(normalize(t, opaque)); err != nil {
		t.Fatalf("keyword lookalikes inside data must stay opaque: %v", err)
	}
}

func TestAuditResourceIdentityRules(t *testing.T) {
	t.Parallel()
	cases := map[string]map[string]any{
		"root identity": {
			"$schema": schemaview.Dialect, "$id": resource.BlockID("demo"), "type": "object",
		},
		"nested identity": {
			"$schema": schemaview.Dialect, "type": "object",
			"properties": map[string]any{"demo": map[string]any{
				"$id":        resource.BlockID("demo"),
				"properties": map[string]any{"inner": map[string]any{"$id": resource.BlockID("inner")}},
			}},
		},
		"mismatched identity": {
			"$schema": schemaview.Dialect, "type": "object",
			"properties": map[string]any{"demo": map[string]any{"$id": resource.BlockID("other")}},
		},
		"non-string identity": {
			"$schema": schemaview.Dialect, "type": "object",
			"properties": map[string]any{"demo": map[string]any{"$id": float64(1)}},
		},
		"nested dialect": {
			"$schema": schemaview.Dialect, "type": "object",
			"properties": map[string]any{"demo": map[string]any{"$schema": schemaview.Dialect}},
		},
	}
	for name, root := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if err := schemaview.Audit(normalize(t, root)); err == nil {
				t.Fatalf("%s must be rejected", name)
			}
		})
	}
}

func TestAuditReferenceRules(t *testing.T) {
	t.Parallel()
	accepted := map[string]map[string]any{
		"local defs":      {"$defs": map[string]any{"body": map[string]any{"type": "object"}}, "$ref": "#/$defs/body"},
		"boolean defs":    {"$defs": map[string]any{"body": true}, "$ref": "#/$defs/body"},
		"escaped tokens":  {"$defs": map[string]any{"a/b": map[string]any{"type": "object"}}, "$ref": "#/$defs/a~1b"},
		"resource root":   {"type": "object", "properties": map[string]any{"echo": map[string]any{"$ref": "#"}}},
		"through applica": {"allOf": []any{map[string]any{"type": "object"}}, "properties": map[string]any{"x": map[string]any{"$ref": "#/allOf/0"}}},
	}
	for name, fragment := range accepted {
		t.Run("accepts "+name, func(t *testing.T) {
			t.Parallel()
			if err := schemaview.Audit(normalize(t, compose(fragment))); err != nil {
				t.Fatalf("%s must be supported: %v", name, err)
			}
		})
	}

	rejected := map[string]map[string]any{
		"dangling":            {"$ref": "#/$defs/missing"},
		"keyword container":   {"$defs": map[string]any{"body": map[string]any{"type": "object"}}, "$ref": "#/$defs"},
		"unknown annotation":  {"x-vendor": map[string]any{"body": map[string]any{"type": "object"}}, "$ref": "#/x-vendor/body"},
		"const data":          {"properties": map[string]any{"p": map[string]any{"const": map[string]any{"body": true}}}, "$ref": "#/properties/p/const/body"},
		"enum data":           {"properties": map[string]any{"p": map[string]any{"enum": []any{map[string]any{"body": true}}}}, "$ref": "#/properties/p/enum/0/body"},
		"required array":      {"required": []any{"a"}, "$ref": "#/required/0"},
		"remote":              {"$ref": "https://example.invalid/x.json"},
		"anchor form":         {"$ref": "#name"},
		"percent encoded":     {"$ref": "#/%24defs/body"},
		"malformed escape":    {"$defs": map[string]any{"body": true}, "$ref": "#/$defs/bo~2dy"},
		"non-string $ref":     {"$ref": float64(1), "type": "object"},
		"index out of bounds": {"allOf": []any{map[string]any{"type": "object"}}, "properties": map[string]any{"x": map[string]any{"$ref": "#/allOf/9"}}},
	}
	for name, fragment := range rejected {
		t.Run("rejects "+name, func(t *testing.T) {
			t.Parallel()
			err := schemaview.Audit(normalize(t, compose(fragment)))
			if name == "non-string $ref" {
				// A non-string is not a reference at all; the compiler reports it.
				if err != nil {
					t.Fatalf("a non-string $ref is not audited as a reference: %v", err)
				}
				return
			}
			if err == nil {
				t.Fatalf("a reference to %s must be rejected", name)
			}
		})
	}
}

func TestAuditRejectsAReferenceDeclaredInTheComposedRoot(t *testing.T) {
	t.Parallel()
	root := map[string]any{
		"$schema": schemaview.Dialect,
		"type":    "object",
		"$defs":   map[string]any{"body": map[string]any{"type": "object"}},
		"allOf":   []any{map[string]any{"$ref": "#/$defs/body"}},
	}
	if err := schemaview.Audit(normalize(t, root)); err == nil {
		t.Fatal("only a composed block may declare a reference")
	}
}

func TestAuditRejectsACrossResourceReference(t *testing.T) {
	t.Parallel()
	root := map[string]any{
		"$schema": schemaview.Dialect,
		"type":    "object",
		"properties": map[string]any{
			"demo":  map[string]any{"$id": resource.BlockID("demo"), "$ref": "#/properties/other/$defs/body"},
			"other": map[string]any{"$id": resource.BlockID("other"), "$defs": map[string]any{"body": map[string]any{"type": "object"}}},
		},
	}
	if err := schemaview.Audit(normalize(t, root)); err == nil {
		t.Fatal("a reference must not leave its block resource")
	}
}

func TestResolveWalksMapsAndArrays(t *testing.T) {
	t.Parallel()
	document := map[string]any{"a": map[string]any{"b": []any{"first", map[string]any{"c": "deep"}}}}
	if value, found := schemaview.Resolve(document, []string{"a", "b", "1", "c"}); !found || value != "deep" {
		t.Fatalf("resolve = %v %v", value, found)
	}
	if value, found := schemaview.Resolve(document, nil); !found || value == nil {
		t.Fatal("an empty path resolves to the document")
	}
	for _, tokens := range [][]string{
		{"missing"}, {"a", "b", "9"}, {"a", "b", "notanindex"}, {"a", "b", "0", "deeper"},
	} {
		if _, found := schemaview.Resolve(document, tokens); found {
			t.Fatalf("%v must not resolve", tokens)
		}
	}
}
