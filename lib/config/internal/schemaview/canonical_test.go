package schemaview_test

import (
	"reflect"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/schemaview"
)

func TestCanonicalizeRewritesNamePositions(t *testing.T) {
	t.Parallel()
	canonical := schemaview.Canonicalize(map[string]any{
		"properties":        map[string]any{"Cache-Region": map[string]any{"type": "string"}},
		"dependentSchemas":  map[string]any{"Data_Dir": map[string]any{"type": "object"}},
		"dependentRequired": map[string]any{"Data_Dir": []any{"Cache-Region"}},
		"required":          []any{"Cache-Region"},
	})

	properties := cast[map[string]any](t, canonical["properties"])
	if _, present := properties["cacheregion"]; !present {
		t.Fatalf("a properties key must be canonicalized: %v", properties)
	}
	dependent := cast[map[string]any](t, canonical["dependentSchemas"])
	if _, present := dependent["datadir"]; !present {
		t.Fatalf("a dependentSchemas key must be canonicalized: %v", dependent)
	}
	triggers := cast[map[string]any](t, canonical["dependentRequired"])
	names := cast[[]any](t, triggers["datadir"])
	if len(names) != 1 || names[0] != "cacheregion" {
		t.Fatalf("dependentRequired triggers and names must be canonicalized: %v", triggers)
	}
	required := cast[[]any](t, canonical["required"])
	if len(required) != 1 || required[0] != "cacheregion" {
		t.Fatalf("required entries must be canonicalized: %v", required)
	}
}

func TestCanonicalizeDescendsApplicators(t *testing.T) {
	t.Parallel()
	canonical := schemaview.Canonicalize(map[string]any{
		"allOf":       []any{map[string]any{"properties": map[string]any{"Cache-Region": true}}, true},
		"prefixItems": []any{map[string]any{"required": []any{"Data_Dir"}}},
		"not":         map[string]any{"properties": map[string]any{"Danger_Mode": true}},
	})
	branches := cast[[]any](t, canonical["allOf"])
	first := cast[map[string]any](t, branches[0])
	properties := cast[map[string]any](t, first["properties"])
	if _, present := properties["cacheregion"]; !present || branches[1] != any(true) {
		t.Fatalf("every applicator branch must be canonicalized: %v", branches)
	}
	tuple := cast[[]any](t, canonical["prefixItems"])
	entry := cast[map[string]any](t, tuple[0])
	required := cast[[]any](t, entry["required"])
	if len(required) != 1 || required[0] != "datadir" {
		t.Fatalf("a prefixItems entry must be canonicalized: %v", tuple)
	}
	negated := cast[map[string]any](t, canonical["not"])
	negatedProperties := cast[map[string]any](t, negated["properties"])
	if _, present := negatedProperties["dangermode"]; !present {
		t.Fatalf("a negated branch must be canonicalized: %v", negated)
	}
}

func TestCanonicalizeLeavesDefinitionNamesAlone(t *testing.T) {
	t.Parallel()
	canonical := schemaview.Canonicalize(map[string]any{
		"$defs":       map[string]any{"Body_Name": map[string]any{"properties": map[string]any{"Cache-Region": true}}},
		"definitions": map[string]any{"Legacy_Name": map[string]any{"type": "object"}},
	})
	defs := cast[map[string]any](t, canonical["$defs"])
	entry, present := defs["Body_Name"].(map[string]any)
	if !present {
		t.Fatalf("a $defs entry name is a label, not a configuration key: %v", defs)
	}
	inner := cast[map[string]any](t, entry["properties"])
	if _, canonicalized := inner["cacheregion"]; !canonicalized {
		t.Fatalf("names inside a definition must still be canonicalized: %v", inner)
	}
	legacy := cast[map[string]any](t, canonical["definitions"])
	if _, present := legacy["Legacy_Name"]; !present {
		t.Fatalf("a definitions entry name is a label too: %v", legacy)
	}
}

func TestCanonicalizeStableDedupesNameArrays(t *testing.T) {
	t.Parallel()
	canonical := schemaview.Canonicalize(map[string]any{
		"required":          []any{"cache_region", "cacheRegion", "data_dir", "CACHE-REGION"},
		"dependentRequired": map[string]any{"trigger": []any{"a_b", "aB", "c"}},
	})
	required := cast[[]any](t, canonical["required"])
	if !reflect.DeepEqual(required, []any{"cacheregion", "datadir"}) {
		t.Fatalf("required must dedupe in first-seen order: %v", required)
	}
	triggers := cast[map[string]any](t, canonical["dependentRequired"])
	names := cast[[]any](t, triggers["trigger"])
	if !reflect.DeepEqual(names, []any{"ab", "c"}) {
		t.Fatalf("a dependent array must dedupe in first-seen order: %v", names)
	}
}

func TestCanonicalizePreservesMalformedNameEntries(t *testing.T) {
	t.Parallel()
	// A malformed entry must reach the compiler unchanged so it reports the
	// ordinary schema error instead of the canonicalizer silently repairing it.
	canonical := schemaview.Canonicalize(map[string]any{
		"required":          []any{"cache_region", float64(1)},
		"dependentRequired": map[string]any{"trigger": "not-an-array"},
	})
	required := cast[[]any](t, canonical["required"])
	if len(required) != 2 || required[1] != float64(1) {
		t.Fatalf("a non-string required entry must survive: %v", required)
	}
	triggers := cast[map[string]any](t, canonical["dependentRequired"])
	if triggers["trigger"] != "not-an-array" {
		t.Fatalf("a malformed dependent value must survive: %v", triggers)
	}
}

func TestCanonicalizeRewritesDataKeysInsideConstAndEnum(t *testing.T) {
	t.Parallel()
	canonical := schemaview.Canonicalize(map[string]any{
		"const": map[string]any{"Cache-Region": map[string]any{"Inner_Key": "v"}},
		"enum":  []any{map[string]any{"Data_Dir": []any{map[string]any{"Deep-Key": 1}}}},
	})
	constant := cast[map[string]any](t, canonical["const"])
	inner := cast[map[string]any](t, constant["cacheregion"])
	if _, present := inner["innerkey"]; !present {
		t.Fatalf("const object keys must be canonicalized recursively: %v", constant)
	}
	alternatives := cast[[]any](t, canonical["enum"])
	first := cast[map[string]any](t, alternatives[0])
	list := cast[[]any](t, first["datadir"])
	deep := cast[map[string]any](t, list[0])
	if _, present := deep["deepkey"]; !present {
		t.Fatalf("enum object keys must be canonicalized through arrays: %v", alternatives)
	}
}

func TestCanonicalizeRewritesReferences(t *testing.T) {
	t.Parallel()
	canonical := schemaview.Canonicalize(map[string]any{
		"$defs":      map[string]any{"Body": map[string]any{"properties": map[string]any{"Cache-Region": true}}},
		"properties": map[string]any{"echo": map[string]any{"$ref": "#/$defs/Body/properties/Cache-Region"}},
	})
	properties := cast[map[string]any](t, canonical["properties"])
	echo := cast[map[string]any](t, properties["echo"])
	if echo["$ref"] != "#/$defs/Body/properties/cacheregion" {
		t.Fatalf("only tokens through name maps are rewritten: %v", echo["$ref"])
	}
}

func TestCanonicalizeCarriesUnsupportedShapesThrough(t *testing.T) {
	t.Parallel()
	canonical := schemaview.Canonicalize(map[string]any{
		"properties": "not-an-object",
		"allOf":      "not-a-list",
		"$defs":      "not-an-object",
		"$ref":       float64(1),
		"title":      "kept",
		"not":        true,
	})
	if canonical["properties"] != "not-an-object" || canonical["allOf"] != "not-a-list" ||
		canonical["$defs"] != "not-an-object" || canonical["$ref"] != float64(1) ||
		canonical["title"] != "kept" || canonical["not"] != any(true) {
		t.Fatalf("malformed and annotation values must be carried through: %v", canonical)
	}
	if got := schemaview.CanonicalizeNode(true); got != any(true) {
		t.Fatalf("a boolean schema is carried through: %v", got)
	}
	if got := schemaview.CanonicalizeReference("#/$defs/bad~2escape"); got != "#/$defs/bad~2escape" {
		t.Fatalf("a malformed reference is carried through for the audit to report: %v", got)
	}
}

func TestCanonicalizeInstanceRewritesEveryKey(t *testing.T) {
	t.Parallel()
	canonical := schemaview.CanonicalizeInstance(map[string]any{
		"Cache-Region": "east",
		"List":         []any{map[string]any{"Item_Key": "x"}, "scalar"},
		"Nested":       map[string]any{"Deep-Key": map[string]any{"Deeper_Key": 1}},
	})
	if _, present := canonical["cacheregion"]; !present {
		t.Fatalf("top-level keys must be canonicalized: %v", canonical)
	}
	list := cast[[]any](t, canonical["list"])
	first := cast[map[string]any](t, list[0])
	if _, present := first["itemkey"]; !present || list[1] != "scalar" {
		t.Fatalf("keys inside arrays must be canonicalized: %v", list)
	}
	nested := cast[map[string]any](t, canonical["nested"])
	deep := cast[map[string]any](t, nested["deepkey"])
	if _, present := deep["deeperkey"]; !present {
		t.Fatalf("keys must be canonicalized at every depth: %v", nested)
	}
}

func TestCollisionReportsOnlyOverwriteMaps(t *testing.T) {
	t.Parallel()
	colliding := map[string]map[string]any{
		"properties":                {"properties": map[string]any{"cache_region": true, "cacheRegion": true}},
		"dependentSchemas":          {"dependentSchemas": map[string]any{"a_b": true, "aB": true}},
		"dependentRequired":         {"dependentRequired": map[string]any{"a_b": []any{"x"}, "aB": []any{"y"}}},
		"nested properties":         {"properties": map[string]any{"inner": map[string]any{"properties": map[string]any{"x_y": true, "xY": true}}}},
		"unreferenced $defs":        {"$defs": map[string]any{"body": map[string]any{"properties": map[string]any{"x_y": true, "xY": true}}}},
		"inside an applicator":      {"allOf": []any{map[string]any{"properties": map[string]any{"x_y": true, "xY": true}}}},
		"inside a single applicat":  {"not": map[string]any{"properties": map[string]any{"x_y": true, "xY": true}}},
		"const object":              {"const": map[string]any{"x_y": 1, "xY": 2}},
		"const nested through list": {"const": map[string]any{"list": []any{map[string]any{"x_y": 1, "xY": 2}}}},
		"enum object":               {"enum": []any{map[string]any{"x_y": 1, "xY": 2}}},
	}
	for name, root := range colliding {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			location, detail, collided := schemaview.Collision(root)
			if !collided {
				t.Fatalf("%s must be reported", name)
			}
			if location == "" || detail == "" {
				t.Fatalf("%s must be located and explained: %q %q", name, location, detail)
			}
		})
	}
}

func TestCollisionIgnoresRedundantAndUnrelatedShapes(t *testing.T) {
	t.Parallel()
	clean := map[string]map[string]any{
		"required duplicates":     {"required": []any{"cache_region", "cacheRegion"}},
		"dependent duplicates":    {"dependentRequired": map[string]any{"t": []any{"a_b", "aB"}}},
		"across allOf branches":   {"allOf": []any{map[string]any{"properties": map[string]any{"x_y": true}}, map[string]any{"properties": map[string]any{"xY": true}}}},
		"across then and else":    {"then": map[string]any{"properties": map[string]any{"x_y": true}}, "else": map[string]any{"properties": map[string]any{"xY": true}}},
		"unrelated annotation":    {"x-vendor": map[string]any{"x_y": 1, "xY": 2}},
		"default and examples":    {"default": map[string]any{"x_y": 1, "xY": 2}, "examples": []any{map[string]any{"a_b": 1, "aB": 2}}},
		"distinct names":          {"properties": map[string]any{"cache_region": true, "data_dir": true}},
		"malformed containers":    {"properties": "not-an-object", "allOf": "not-a-list", "$defs": "not-an-object"},
		"boolean schema children": {"properties": map[string]any{"a": true}, "not": true},
	}
	for name, root := range clean {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if location, _, collided := schemaview.Collision(root); collided {
				t.Fatalf("%s must not be reported as a collision at %s", name, location)
			}
		})
	}
}

func TestTwinNamesIsDeterministic(t *testing.T) {
	t.Parallel()
	declared := map[string]any{"cacheRegion": true, "cache_region": true, "Cache-Region": true}
	for range 32 {
		_, detail, collided := schemaview.TwinNames(declared, []string{"properties"})
		if !collided || detail == "" {
			t.Fatal("twins must always be reported")
		}
	}
	if _, _, collided := schemaview.TwinNames(map[string]any{"a": 1, "b": 2}, nil); collided {
		t.Fatal("distinct names are not twins")
	}
}

func TestDataCollisionWalksArraysAndScalars(t *testing.T) {
	t.Parallel()
	if _, _, collided := schemaview.DataCollision([]any{"scalar", float64(1), nil}, nil); collided {
		t.Fatal("scalars carry no keys")
	}
	if _, _, collided := schemaview.DataCollision(map[string]any{"a": []any{map[string]any{"x_y": 1, "xY": 2}}}, nil); !collided {
		t.Fatal("a twin nested through an array must be found")
	}
}
