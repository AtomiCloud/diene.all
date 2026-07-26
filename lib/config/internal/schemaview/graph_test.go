package schemaview_test

import (
	"slices"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/resource"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
)

func TestKeywordSetsCoverTheSupportedSubset(t *testing.T) {
	t.Parallel()
	for _, keyword := range []string{"$defs", "definitions", "properties", "dependentSchemas"} {
		if !slices.Contains(schemaview.NamedSchemaKeywords(), keyword) {
			t.Fatalf("named schema keyword %q missing", keyword)
		}
	}
	for _, keyword := range []string{"additionalProperties", "unevaluatedProperties", "items", "unevaluatedItems", "contains", "not", "if", "then", "else"} {
		if !slices.Contains(schemaview.SingleSchemaKeywords(), keyword) {
			t.Fatalf("single schema keyword %q missing", keyword)
		}
	}
	for _, keyword := range []string{"allOf", "anyOf", "oneOf", "prefixItems"} {
		if !slices.Contains(schemaview.ListSchemaKeywords(), keyword) {
			t.Fatalf("list schema keyword %q missing", keyword)
		}
	}
	for _, keyword := range []string{"properties", "dependentSchemas", "dependentRequired"} {
		if !schemaview.IsNameBearingKeyword(keyword) {
			t.Fatalf("name-bearing keyword %q missing", keyword)
		}
	}
	if schemaview.IsNameBearingKeyword("$defs") {
		t.Fatal("a definition label is not a configuration key name")
	}
	if !slices.Contains(schemaview.NameArrayKeywords(), "required") {
		t.Fatal("required holds a name array")
	}
	for _, keyword := range []string{"const", "enum"} {
		if !slices.Contains(schemaview.DataKeywords(), keyword) {
			t.Fatalf("data keyword %q missing", keyword)
		}
	}
}

func TestGraphEntersOnlySchemaBearingEdges(t *testing.T) {
	t.Parallel()
	graph := schemaview.NewGraph(map[string]any{
		"$defs":      map[string]any{"body": map[string]any{"type": "object"}, "flag": true},
		"properties": map[string]any{"a": map[string]any{"type": "string"}},
		"allOf":      []any{map[string]any{"type": "object"}, "not-a-schema"},
		"not":        map[string]any{"type": "object"},
		"const":      map[string]any{"looks": map[string]any{"like": "a schema"}},
		"enum":       []any{map[string]any{"also": "data"}},
		"x-vendor":   map[string]any{"opaque": map[string]any{"type": "object"}},
		"default":    map[string]any{"type": "object"},
	})

	for _, pointer := range []string{"#", "#/$defs/body", "#/$defs/flag", "#/properties/a", "#/allOf/0", "#/not"} {
		if _, found := graph.Nodes()[pointer]; !found {
			t.Fatalf("%s must be an approved schema node", pointer)
		}
	}
	for _, pointer := range []string{
		"#/const", "#/const/looks", "#/enum/0", "#/x-vendor", "#/x-vendor/opaque",
		"#/default", "#/allOf/1", "#/$defs", "#/properties",
	} {
		if _, found := graph.Nodes()[pointer]; found {
			t.Fatalf("%s must stay opaque, not become a schema node", pointer)
		}
	}
}

func TestGraphRecordsResourceRootsAndReferences(t *testing.T) {
	t.Parallel()
	graph := schemaview.NewGraph(map[string]any{
		"properties": map[string]any{
			"demo": map[string]any{
				"$id":        resource.BlockID("demo"),
				"$defs":      map[string]any{"body": map[string]any{"type": "object"}},
				"properties": map[string]any{"echo": map[string]any{"$ref": "#/$defs/body"}},
			},
		},
	})

	root, found := graph.Node([]string{})
	if !found || len(root.Resource) != 0 {
		t.Fatalf("the document root is its own resource: %+v", root)
	}
	inner, found := graph.Node([]string{"properties", "demo", "properties", "echo"})
	if !found || !schemaview.EqualTokens(inner.Resource, []string{"properties", "demo"}) {
		t.Fatalf("a node inside a block belongs to the block resource: %+v", inner)
	}
	references := graph.References()
	if len(references) != 1 || references[0].Value != "#/$defs/body" {
		t.Fatalf("exactly the one real reference must be recorded: %+v", references)
	}
	if !schemaview.EqualTokens(references[0].Role.Resource, []string{"properties", "demo"}) {
		t.Fatalf("a reference carries its resource: %+v", references[0].Role)
	}
}

func TestGraphIgnoresReferenceLookalikesInData(t *testing.T) {
	t.Parallel()
	graph := schemaview.NewGraph(map[string]any{
		"const":    map[string]any{"$ref": "#/$defs/body"},
		"enum":     []any{map[string]any{"$ref": "#/$defs/body"}},
		"x-vendor": map[string]any{"$ref": "#/$defs/body"},
	})
	if len(graph.References()) != 0 {
		t.Fatalf("a $ref inside data is literal content: %+v", graph.References())
	}
}

func TestSharedHelpers(t *testing.T) {
	t.Parallel()
	if schemaview.CanonicalKey("Cache-Region") != "cacheregion" {
		t.Fatal("the canonical rule must match the family contract")
	}
	if got := schemaview.SortedNames(map[string]any{"b": 1, "a": 2}); got[0] != "a" || got[1] != "b" {
		t.Fatalf("names must be sorted: %v", got)
	}
	if schemaview.Index(3) != "3" {
		t.Fatal("an index renders as its decimal token")
	}
	if position, err := schemaview.ParseIndex("3"); err != nil || position != 3 {
		t.Fatalf("index parse = %v %v", position, err)
	}
	for _, token := range []string{"x", "-1", ""} {
		if _, err := schemaview.ParseIndex(token); err == nil {
			t.Fatalf("%q is not an array index", token)
		}
	}
}

func TestNormalizeFlattensTypedContainersAndFailsFast(t *testing.T) {
	t.Parallel()
	normalized, err := schemaview.Normalize(map[string]any{
		"properties": map[string]map[string]any{"a": {"type": "string"}},
	})
	if err != nil {
		t.Fatalf("normalize: %v", err)
	}
	properties, isObject := normalized["properties"].(map[string]any)
	if !isObject {
		t.Fatalf("a typed container must flatten: %T", normalized["properties"])
	}
	if _, isObject = properties["a"].(map[string]any); !isObject {
		t.Fatalf("a typed property value must flatten: %T", properties["a"])
	}
	if _, err = schemaview.Normalize(map[string]any{"x": make(chan int)}); err == nil {
		t.Fatal("an unencodable schema must fail fast")
	}
	cyclic := map[string]any{"type": "object"}
	cyclic["self"] = cyclic
	if _, err = schemaview.Normalize(cyclic); err == nil {
		t.Fatal("a cyclic schema must fail fast rather than hang")
	}
}

func TestNodesAsAnyMirrorsTheNodeIndex(t *testing.T) {
	t.Parallel()
	graph := schemaview.NewGraph(map[string]any{"properties": map[string]any{"a": true}})
	mirrored := schemaview.NodesAsAny(graph)
	if len(mirrored) != len(graph.Nodes()) {
		t.Fatalf("the mirror must cover every node: %v vs %v", len(mirrored), len(graph.Nodes()))
	}
	for pointer := range graph.Nodes() {
		if _, present := mirrored[pointer]; !present {
			t.Fatalf("%s missing from the mirror", pointer)
		}
	}
}

// cast asserts value has type T, failing the test with the actual type otherwise.
func cast[T any](t *testing.T, value any) T {
	t.Helper()
	typed, ok := value.(T)
	if !ok {
		t.Fatalf("expected %T, got %T (%v)", typed, value, value)
	}
	return typed
}
