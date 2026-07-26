package schemaview_test

import (
	"reflect"
	"slices"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
)

// document normalizes schema and wraps it, failing the test on an authoring fault.
func document(t *testing.T, schema map[string]any) schemaview.Document {
	t.Helper()
	normalized, err := schemaview.Normalize(schema)
	if err != nil {
		t.Fatalf("normalize: %v", err)
	}
	return schemaview.NewDocument(normalized)
}

func TestNormalizeFlattensTypedContainers(t *testing.T) {
	t.Parallel()
	// A legal authored fragment may use typed containers; normalizing must yield
	// the generic tree the compiler sees.
	normalized, err := schemaview.Normalize(map[string]any{
		"properties": map[string]map[string]any{"a": {"type": "string"}},
	})
	if err != nil {
		t.Fatalf("normalize: %v", err)
	}
	properties, ok := normalized["properties"].(map[string]any)
	if !ok {
		t.Fatalf("typed properties container not flattened: %T", normalized["properties"])
	}
	if _, ok := properties["a"].(map[string]any); !ok {
		t.Fatalf("typed property value not flattened: %T", properties["a"])
	}
}

func TestNormalizeRejectsUnencodableAndCyclic(t *testing.T) {
	t.Parallel()
	if _, err := schemaview.Normalize(map[string]any{"x": make(chan int)}); err == nil {
		t.Fatal("an unencodable schema must fail fast")
	}
	cyclic := map[string]any{"type": "object"}
	cyclic["self"] = cyclic
	if _, err := schemaview.Normalize(cyclic); err == nil {
		t.Fatal("a cyclic schema must fail fast rather than hang")
	}
}

func TestCollisionShapes(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name   string
		schema map[string]any
		want   string
	}{
		{
			name:   "top level",
			schema: map[string]any{"properties": map[string]any{"cache_region": map[string]any{}, "cacheRegion": map[string]any{}}},
			want:   "(root)",
		},
		{
			name: "nested property",
			schema: map[string]any{"properties": map[string]any{
				"app": map[string]any{"properties": map[string]any{"data-dir": map[string]any{}, "dataDir": map[string]any{}}},
			}},
			want: "app",
		},
		{
			name: "array items",
			schema: map[string]any{"properties": map[string]any{
				"list": map[string]any{"items": map[string]any{"properties": map[string]any{"a_b": map[string]any{}, "aB": map[string]any{}}}},
			}},
			want: "list[]",
		},
		{
			name: "typed authoring container",
			schema: map[string]any{"properties": map[string]map[string]any{
				"cache_region": {"type": "string"}, "cacheRegion": {"type": "string"},
			}},
			want: "(root)",
		},
		{
			name: "unreferenced $defs entry",
			schema: map[string]any{
				"type":  "object",
				"$defs": map[string]any{"Widget": map[string]any{"properties": map[string]any{"a_b": map[string]any{}, "aB": map[string]any{}}}},
			},
			want: "<$defs:Widget>",
		},
		{
			name: "legacy definitions entry",
			schema: map[string]any{
				"definitions": map[string]any{"Old": map[string]any{"properties": map[string]any{"x_y": map[string]any{}, "xY": map[string]any{}}}},
			},
			want: "<definitions:Old>",
		},
		{
			name: "across allOf branches",
			schema: map[string]any{"allOf": []any{
				map[string]any{"properties": map[string]any{"cache_region": map[string]any{}}},
				map[string]any{"properties": map[string]any{"cacheRegion": map[string]any{}}},
			}},
			want: "(root)",
		},
		{
			name: "between own properties and a $ref target",
			schema: map[string]any{
				"$defs":      map[string]any{"extra": map[string]any{"properties": map[string]any{"cacheRegion": map[string]any{}}}},
				"properties": map[string]any{"cache_region": map[string]any{}},
				"allOf":      []any{map[string]any{"$ref": "#/$defs/extra"}},
			},
			want: "(root)",
		},
		{
			name: "inside prefixItems",
			schema: map[string]any{"prefixItems": []any{
				map[string]any{"properties": map[string]any{"a-b": map[string]any{}, "aB": map[string]any{}}},
			}},
			want: "<prefixItems:0>",
		},
		{
			name: "inside patternProperties",
			schema: map[string]any{"patternProperties": map[string]any{
				"^x": map[string]any{"properties": map[string]any{"m_n": map[string]any{}, "mN": map[string]any{}}},
			}},
			want: "<patternProperties:^x>",
		},
		{
			name: "inside if/then",
			schema: map[string]any{
				"then": map[string]any{"properties": map[string]any{"p_q": map[string]any{}, "pQ": map[string]any{}}},
			},
			want: "(root)",
		},
		{
			name: "inside not",
			schema: map[string]any{
				"not": map[string]any{"properties": map[string]any{"r_s": map[string]any{}, "rS": map[string]any{}}},
			},
			want: "<not>",
		},
		{
			name: "inside additionalProperties",
			schema: map[string]any{
				"additionalProperties": map[string]any{"properties": map[string]any{"t_u": map[string]any{}, "tU": map[string]any{}}},
			},
			want: "<additionalProperties>",
		},
		{
			name: "inside contains",
			schema: map[string]any{
				"contains": map[string]any{"properties": map[string]any{"v_w": map[string]any{}, "vW": map[string]any{}}},
			},
			want: "<contains>",
		},
		{
			name: "nested inside dependentSchemas",
			schema: map[string]any{
				"dependentSchemas": map[string]any{"flag": map[string]any{"properties": map[string]any{
					"inner": map[string]any{"properties": map[string]any{"y_z": map[string]any{}, "yZ": map[string]any{}}},
				}}},
			},
			want: "<dependentSchemas:flag>.inner",
		},
		{
			name: "between own properties and a dependent schema",
			schema: map[string]any{
				"properties":       map[string]any{"cache_region": map[string]any{}},
				"dependentSchemas": map[string]any{"flag": map[string]any{"properties": map[string]any{"cacheRegion": map[string]any{}}}},
			},
			want: "(root)",
		},
		{
			name:   "boolean property schemas",
			schema: map[string]any{"properties": map[string]any{"cache_region": true, "cacheRegion": true}},
			want:   "(root)",
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			location, detail, collided := document(t, testCase.schema).Collision()
			if !collided || location != testCase.want {
				t.Fatalf("collision = %q %v, want %q", location, collided, testCase.want)
			}
			if detail == "" {
				t.Fatal("a collision must carry an explanatory detail")
			}
		})
	}
}

func TestCollisionAcceptsDistinctSpellings(t *testing.T) {
	t.Parallel()
	// Exercises non-object property values, items recursion, boolean subschemas,
	// and a definition that repeats the SAME spelling across branches (legal).
	clean := map[string]any{
		"$defs": map[string]any{"shared": map[string]any{"properties": map[string]any{"cache_region": map[string]any{}}}},
		// The boolean and string entries are not subschemas and must be skipped by
		// both the structural walk and the expansion.
		"allOf": []any{
			map[string]any{"$ref": "#/$defs/shared"},
			map[string]any{"properties": map[string]any{"cache_region": map[string]any{"type": "string"}}},
			true,
			"not-a-schema",
		},
		"anyOf": []any{false},
		"properties": map[string]any{
			"flag": true,
			"list": map[string]any{"items": map[string]any{"properties": map[string]any{"ok": map[string]any{}}}},
			"app":  map[string]any{"properties": map[string]any{"landscape": map[string]any{}}},
		},
		"additionalProperties": false,
	}
	if location, _, collided := document(t, clean).Collision(); collided {
		t.Fatalf("distinct (and repeated-identical) spellings must not collide: %q", location)
	}
}

func TestCollisionTerminatesOnReferenceCycle(t *testing.T) {
	t.Parallel()
	// node references itself through allOf; expansion must visit it once.
	cyclic := map[string]any{
		"$defs": map[string]any{
			"node": map[string]any{
				"properties": map[string]any{"child": map[string]any{"$ref": "#/$defs/node"}},
				"allOf":      []any{map[string]any{"$ref": "#/$defs/node"}},
			},
		},
		"properties": map[string]any{"root": map[string]any{"$ref": "#/$defs/node"}},
	}
	if _, _, collided := document(t, cyclic).Collision(); collided {
		t.Fatal("a self-referential schema must terminate without a false collision")
	}
}

func TestPointerResolvesEscapesAndRejectsRemote(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"$defs": map[string]any{
			"a/b":  map[string]any{"title": "slash"},
			"c~d":  map[string]any{"title": "tilde"},
			"list": []any{map[string]any{"title": "first"}},
		},
	})
	if target, ok := doc.Pointer("#/$defs/a~1b"); !ok || target["title"] != "slash" {
		t.Fatalf("~1 must decode to a slash: %v %v", target, ok)
	}
	if target, ok := doc.Pointer("#/$defs/c~0d"); !ok || target["title"] != "tilde" {
		t.Fatalf("~0 must decode to a tilde: %v %v", target, ok)
	}
	if target, ok := doc.Pointer("#/$defs/list/0"); !ok || target["title"] != "first" {
		t.Fatalf("array index token must resolve: %v %v", target, ok)
	}
	if root, ok := doc.Pointer("#"); !ok || !reflect.DeepEqual(root, doc.Root()) {
		t.Fatal("# must resolve to the document root")
	}
	for _, reference := range []string{
		"https://example.invalid/schema.json",
		"#/$defs/missing",
		"#/$defs/list/9",
		"#/$defs/list/notanindex",
		"#/$defs/a~1b/title/deeper",
		"#/$defs/list",
	} {
		if _, ok := doc.Pointer(reference); ok {
			t.Fatalf("reference %q must not resolve", reference)
		}
	}
}

func TestAlignRewritesKeysToSchemaSpelling(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
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
			"tuple": map[string]any{
				"type":        "array",
				"prefixItems": []any{map[string]any{"type": "object", "properties": map[string]any{"first_key": map[string]any{}}}},
			},
			"scalars": map[string]any{"type": "array", "items": map[string]any{"type": "integer"}},
			"opaque":  map[string]any{"type": "object"},
		},
	})
	instance := map[string]any{
		"cacheRegion": "r",
		"nested":      map[string]any{"innerKey": "v"},
		"list":        []any{map[string]any{"itemKey": "x"}, "not-a-map"},
		"tuple":       []any{map[string]any{"firstKey": "t"}},
		"scalars":     []any{1, 2},
		"opaque":      map[string]any{"free-form": "kept"},
		"extra":       "kept",
		"orphanMap":   map[string]any{"a": 1},
	}
	aligned := doc.Align(schemaview.Position{doc.Root()}, instance)

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
	tuple, ok := aligned["tuple"].([]any)
	if !ok {
		t.Fatalf("tuple not preserved: %v", aligned["tuple"])
	}
	tupleFirst, ok := tuple[0].(map[string]any)
	if !ok || tupleFirst["first_key"] != "t" {
		t.Fatalf("prefixItems element key not aligned: %v", tuple[0])
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
	if opaque, ok := aligned["opaque"].(map[string]any); !ok || opaque["free-form"] != "kept" {
		t.Fatalf("properties-less object schema must keep its keys: %v", aligned["opaque"])
	}
}

func TestAlignFollowsRefAndComposition(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"$defs": map[string]any{
			"app": map[string]any{"properties": map[string]any{"cache_region": map[string]any{"type": "string"}}},
		},
		"properties": map[string]any{
			"viaRef": map[string]any{"$ref": "#/$defs/app"},
			"viaAllOf": map[string]any{"allOf": []any{
				map[string]any{"properties": map[string]any{"data_dir": map[string]any{"type": "string"}}},
				map[string]any{"$ref": "#/$defs/app"},
			}},
		},
	})
	aligned := doc.Align(schemaview.Position{doc.Root()}, map[string]any{
		"viaRef":   map[string]any{"cacheRegion": "a"},
		"viaAllOf": map[string]any{"dataDir": "b", "CacheRegion": "c"},
	})

	viaRef, ok := aligned["viaRef"].(map[string]any)
	if !ok || viaRef["cache_region"] != "a" {
		t.Fatalf("alignment must follow a local $ref: %v", aligned["viaRef"])
	}
	viaAllOf, ok := aligned["viaAllOf"].(map[string]any)
	if !ok || viaAllOf["data_dir"] != "b" || viaAllOf["cache_region"] != "c" {
		t.Fatalf("alignment must union composed branches: %v", aligned["viaAllOf"])
	}
}

func TestAlignTerminatesOnRecursiveSchema(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"$defs": map[string]any{
			"node": map[string]any{"properties": map[string]any{
				"child_node": map[string]any{"$ref": "#/$defs/node"},
				"leaf_value": map[string]any{"type": "string"},
			}},
		},
		"$ref": "#/$defs/node",
	})
	aligned := doc.Align(schemaview.Position{doc.Root()}, map[string]any{
		"childNode": map[string]any{"childNode": map[string]any{"leafValue": "deep"}},
	})
	level1, ok := aligned["child_node"].(map[string]any)
	if !ok {
		t.Fatalf("recursive alignment level 1 failed: %v", aligned)
	}
	level2, ok := level1["child_node"].(map[string]any)
	if !ok || level2["leaf_value"] != "deep" {
		t.Fatalf("recursive alignment level 2 failed: %v", level1)
	}
}

func TestExpandAndPropertiesUnionBranches(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"$defs":      map[string]any{"extra": map[string]any{"properties": map[string]any{"b": map[string]any{}}}},
		"properties": map[string]any{"a": map[string]any{}},
		"allOf":      []any{map[string]any{"$ref": "#/$defs/extra"}},
		"not":        map[string]any{"properties": map[string]any{"negated": map[string]any{}}},
	})
	expanded := doc.Expand(schemaview.Position{doc.Root()})
	properties := schemaview.Properties(expanded)
	if _, ok := properties["a"]; !ok {
		t.Fatal("own properties must be in the combined view")
	}
	if _, ok := properties["b"]; !ok {
		t.Fatal("referenced branch properties must be in the combined view")
	}
	if _, ok := properties["negated"]; ok {
		t.Fatal("a negated branch's spellings must not join the accepted view")
	}
}

func TestExpandSkipsNilAndBooleanBranches(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"properties": map[string]any{"a": map[string]any{}},
		"allOf":      []any{true, "not-a-schema"},
		"if":         true,
	})
	if got := doc.Expand(schemaview.Position{doc.Root()}); len(got) != 1 {
		t.Fatalf("boolean and non-object branches contribute nothing: %d", len(got))
	}
	if got := doc.Expand(schemaview.Position{nil}); len(got) != 0 {
		t.Fatalf("a nil node expands to nothing: %d", len(got))
	}
}

func TestItemsSplitsTupleAndListPositions(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"prefixItems": []any{map[string]any{"title": "first"}, true},
		"items":       map[string]any{"title": "rest"},
	})
	position := schemaview.Position{doc.Root()}
	got := schemaview.Items(position, 0)
	if len(got) != 1 || got[0]["title"] != "first" {
		t.Fatalf("an index inside prefixItems is constrained by that entry alone: %v", got)
	}
	if boolEntry := schemaview.Items(position, 1); len(boolEntry) != 0 {
		t.Fatalf("a boolean prefixItems entry contributes nothing and does not fall to items: %v", boolEntry)
	}
	got = schemaview.Items(position, 5)
	if len(got) != 1 || got[0]["title"] != "rest" {
		t.Fatalf("an index past prefixItems falls to items: %v", got)
	}
}

func TestAlignSeparatesPrefixItemsFromItems(t *testing.T) {
	t.Parallel()
	// Element 0 must align only through prefixItems and element 1 only through
	// items; unioning them would rewrite each element with the other's spellings.
	doc := document(t, map[string]any{
		"properties": map[string]any{"tuple": map[string]any{
			"prefixItems": []any{map[string]any{"properties": map[string]any{"first_key": map[string]any{}}}},
			"items":       map[string]any{"properties": map[string]any{"rest_key": map[string]any{}}},
		}},
	})
	aligned := doc.Align(schemaview.Position{doc.Root()}, map[string]any{
		"tuple": []any{map[string]any{"firstKey": "a"}, map[string]any{"restKey": "b"}},
	})
	tuple, ok := aligned["tuple"].([]any)
	if !ok || len(tuple) != 2 {
		t.Fatalf("tuple not preserved: %v", aligned["tuple"])
	}
	head, ok := tuple[0].(map[string]any)
	if !ok || head["first_key"] != "a" {
		t.Fatalf("prefixItems element must align through its own entry: %v", tuple[0])
	}
	if _, leaked := head["rest_key"]; leaked {
		t.Fatalf("items spellings must not reach a prefixItems element: %v", head)
	}
	tail, ok := tuple[1].(map[string]any)
	if !ok || tail["rest_key"] != "b" {
		t.Fatalf("element past prefixItems must align through items: %v", tuple[1])
	}
}

func TestAlignIndexesBooleanPropertySchemas(t *testing.T) {
	t.Parallel()
	// A boolean property schema still claims its canonical spelling, so the
	// instance key must be rewritten onto it.
	doc := document(t, map[string]any{"properties": map[string]any{"cache_region": true}})
	aligned := doc.Align(schemaview.Position{doc.Root()}, map[string]any{"cacheRegion": "east"})
	if aligned["cache_region"] != "east" {
		t.Fatalf("a boolean property schema must still align its key: %v", aligned)
	}
}

func TestAlignRoutesThroughPatternAndAdditionalProperties(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"properties": map[string]any{"known": map[string]any{"properties": map[string]any{"known_key": map[string]any{}}}},
		// "[" is an uncompilable pattern and "^bool" is a boolean subschema; both
		// must be skipped without failing alignment.
		"patternProperties": map[string]any{
			"^svc":  map[string]any{"properties": map[string]any{"cache_region": map[string]any{}}},
			"[":     map[string]any{},
			"^bool": true,
		},
		"additionalProperties": map[string]any{
			"properties": map[string]any{"fallback_key": map[string]any{}},
		},
	})
	aligned := doc.Align(schemaview.Position{doc.Root()}, map[string]any{
		"known":  map[string]any{"knownKey": "k"},
		"svcOne": map[string]any{"cacheRegion": "p"},
		"other":  map[string]any{"fallbackKey": "f"},
	})
	known, ok := aligned["known"].(map[string]any)
	if !ok || known["known_key"] != "k" {
		t.Fatalf("declared property must align through properties: %v", aligned["known"])
	}
	pattern, ok := aligned["svcOne"].(map[string]any)
	if !ok || pattern["cache_region"] != "p" {
		t.Fatalf("pattern-matched key must align through patternProperties: %v", aligned["svcOne"])
	}
	fallback, ok := aligned["other"].(map[string]any)
	if !ok || fallback["fallback_key"] != "f" {
		t.Fatalf("unmatched key must align through additionalProperties: %v", aligned["other"])
	}
	if _, leaked := pattern["fallback_key"]; leaked {
		t.Fatal("additionalProperties must not apply to a pattern-matched key")
	}
}

func TestValuePositionAppliesObjectApplicability(t *testing.T) {
	t.Parallel()
	doc := document(t, map[string]any{
		"properties":           map[string]any{"boolish": true, "declared": map[string]any{"title": "declared"}},
		"patternProperties":    map[string]any{"^svc": map[string]any{"title": "pattern"}},
		"additionalProperties": map[string]any{"title": "additional"},
	})
	expanded := doc.Expand(schemaview.Position{doc.Root()})

	if got := schemaview.ValuePosition(expanded, "declared"); len(got) != 1 || got[0]["title"] != "declared" {
		t.Fatalf("a declared property resolves to its own schema: %v", got)
	}
	if got := schemaview.ValuePosition(expanded, "boolish"); len(got) != 0 {
		t.Fatalf("a boolean property schema is described but carries no subschema: %v", got)
	}
	if got := schemaview.ValuePosition(expanded, "svcOne"); len(got) != 1 || got[0]["title"] != "pattern" {
		t.Fatalf("a pattern-matched key resolves to the pattern schema: %v", got)
	}
	if got := schemaview.ValuePosition(expanded, "unknown"); len(got) != 1 || got[0]["title"] != "additional" {
		t.Fatalf("an undescribed key falls back to additionalProperties: %v", got)
	}
}

func TestValuePositionIsDecidedPerComposedBranch(t *testing.T) {
	t.Parallel()
	// Branch A declares "known"; branch B does not, so branch B's own
	// additionalProperties also constrains that key. Deciding applicability from
	// the globally unioned property set would suppress branch B and lose the
	// nested alignment it carries.
	doc := document(t, map[string]any{
		"allOf": []any{
			map[string]any{"properties": map[string]any{"known": map[string]any{"type": "object"}}},
			map[string]any{"additionalProperties": map[string]any{
				"properties": map[string]any{"nested_key": map[string]any{"type": "string"}},
			}},
		},
	})
	aligned := doc.Align(schemaview.Position{doc.Root()}, map[string]any{
		"known": map[string]any{"nestedKey": "v"},
	})
	known, ok := aligned["known"].(map[string]any)
	if !ok || known["nested_key"] != "v" {
		t.Fatalf("a sibling branch's additionalProperties must still align the value: %v", aligned["known"])
	}
}

func TestNameIndexIsDeterministic(t *testing.T) {
	t.Parallel()
	properties := map[string]schemaview.Position{
		"cacheRegion":  {},
		"cache_region": {},
		"Cache-Region": {},
	}
	for range 32 {
		index := schemaview.NameIndex(properties)
		if index["cacheregion"] != "Cache-Region" {
			t.Fatalf("a residual collision must resolve to the sorted-first name: %q", index["cacheregion"])
		}
	}
}

func TestJoinRendersLocationPaths(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		schemaview.Join("", "properties", "app"):     "app",
		schemaview.Join("app", "properties", "name"): "app.name",
		schemaview.Join("list", "items", ""):         "list[]",
		schemaview.Join("", "$defs", "Widget"):       "<$defs:Widget>",
		schemaview.Join("", "allOf", "1"):            "<allOf:1>",
		schemaview.Join("app", "not", ""):            "app<not>",
	}
	for got, want := range cases {
		if got != want {
			t.Fatalf("Join = %q, want %q", got, want)
		}
	}
}

func TestKeywordSetsAreStable(t *testing.T) {
	t.Parallel()
	// The keyword sets are the traversal contract; assert the draft-2020-12
	// locations the loader depends on are present.
	for _, keyword := range []string{"allOf", "anyOf", "oneOf", "if", "then", "else"} {
		if !slices.Contains(schemaview.CompositionKeywords(), keyword) {
			t.Fatalf("composition keyword %q missing", keyword)
		}
	}
	if slices.Contains(schemaview.CompositionKeywords(), "not") {
		t.Fatal("not must not be treated as an accepted-spelling branch")
	}
	for _, keyword := range []string{"properties", "patternProperties", "dependentSchemas", "$defs", "definitions"} {
		if !slices.Contains(schemaview.NamedSubschemaKeywords(), keyword) {
			t.Fatalf("named subschema keyword %q missing", keyword)
		}
	}
	for _, keyword := range []string{"additionalProperties", "unevaluatedProperties", "propertyNames", "items", "contains", "not", "if", "then", "else"} {
		if !slices.Contains(schemaview.SingleSubschemaKeywords(), keyword) {
			t.Fatalf("single subschema keyword %q missing", keyword)
		}
	}
	for _, keyword := range []string{"allOf", "anyOf", "oneOf", "prefixItems"} {
		if !slices.Contains(schemaview.ListSubschemaKeywords(), keyword) {
			t.Fatalf("list subschema keyword %q missing", keyword)
		}
	}
}
