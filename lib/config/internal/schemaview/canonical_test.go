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

// opaquePayload carries deeply nested authored keys, canonical twins, and
// keyword lookalikes — none of which may be rewritten or acted on.
func opaquePayload() map[string]any {
	return map[string]any{
		"Cache_Region": float64(1),
		"cacheRegion":  float64(2),
		"$ref":         "https://example.invalid/x.json",
		"patternProperties": map[string]any{
			"^Deep_Key": map[string]any{"Nested-Twin": 1, "nestedTwin": 2},
		},
		"list": []any{
			map[string]any{"Inside_Array": map[string]any{"Deeper_Key": "v"}},
			"scalar",
		},
	}
}

// requireOpaque asserts value preserved every authored key of [opaquePayload].
func requireOpaque(t *testing.T, value any, what string) {
	t.Helper()
	payload := cast[map[string]any](t, value)
	for _, name := range []string{"Cache_Region", "cacheRegion", "$ref", "patternProperties"} {
		if _, present := payload[name]; !present {
			t.Fatalf("%s lost the authored key %q: %v", what, name, payload)
		}
	}
	if payload["Cache_Region"] != float64(1) || payload["cacheRegion"] != float64(2) {
		t.Fatalf("%s collapsed canonical twins: %v", what, payload)
	}
	patterns := cast[map[string]any](t, payload["patternProperties"])
	twins := cast[map[string]any](t, patterns["^Deep_Key"])
	if twins["Nested-Twin"] != 1 || twins["nestedTwin"] != 2 {
		t.Fatalf("%s rewrote nested opaque keys: %v", what, twins)
	}
	list := cast[[]any](t, payload["list"])
	entry := cast[map[string]any](t, list[0])
	deeper := cast[map[string]any](t, entry["Inside_Array"])
	if deeper["Deeper_Key"] != "v" || list[1] != "scalar" {
		t.Fatalf("%s rewrote keys inside an array: %v", what, list)
	}
}

func TestCloneOpaquePreservesEveryAuthoredKey(t *testing.T) {
	t.Parallel()
	source := opaquePayload()
	cloned := schemaview.CloneOpaque(source)
	requireOpaque(t, cloned, "CloneOpaque")

	// It is a real deep copy: mutating the clone cannot reach the source.
	clonedMap := cast[map[string]any](t, cloned)
	clonedMap["Cache_Region"] = "mutated"
	cast[map[string]any](t, clonedMap["patternProperties"])["^Deep_Key"] = "mutated"
	cast[[]any](t, clonedMap["list"])[1] = "mutated"
	requireOpaque(t, source, "the source after mutating its clone")

	if got := schemaview.CloneOpaque("scalar"); got != "scalar" {
		t.Fatalf("a scalar clones to itself: %v", got)
	}
	if got := schemaview.CloneOpaque(nil); got != nil {
		t.Fatalf("nil clones to nil: %v", got)
	}
}

func TestCanonicalizePreservesOpaqueAnnotations(t *testing.T) {
	t.Parallel()
	// Every location the supported subset calls opaque must survive byte-for-byte.
	canonical := schemaview.Canonicalize(map[string]any{
		"default":  opaquePayload(),
		"examples": []any{opaquePayload()},
		"x-vendor": opaquePayload(),
		"title":    "kept",
	})
	requireOpaque(t, canonical["default"], "default")
	requireOpaque(t, cast[[]any](t, canonical["examples"])[0], "examples")
	requireOpaque(t, canonical["x-vendor"], "an unknown annotation")
	if canonical["title"] != "kept" {
		t.Fatalf("a scalar annotation must survive: %v", canonical["title"])
	}
}

func TestCanonicalizePreservesOpaqueMalformedShapes(t *testing.T) {
	t.Parallel()
	// A malformed value at a schema position reaches the compiler exactly as
	// authored, so it reports the ordinary error on the author's own bytes.
	canonical := schemaview.Canonicalize(map[string]any{
		// A name map must be an OBJECT; a list here is malformed, so it is opaque.
		"properties":        []any{opaquePayload()},
		"$defs":             "not-an-object",
		"allOf":             opaquePayload(),
		"required":          opaquePayload(),
		"dependentRequired": map[string]any{"trigger": opaquePayload()},
		// A boolean schema at a single-schema position is carried through.
		"not": true,
	})
	requireOpaque(t, cast[[]any](t, canonical["properties"])[0], "a malformed properties value")
	if canonical["$defs"] != "not-an-object" {
		t.Fatalf("a malformed $defs value must survive: %v", canonical["$defs"])
	}
	if canonical["not"] != any(true) {
		t.Fatalf("a boolean schema must survive: %v", canonical["not"])
	}
	requireOpaque(t, canonical["allOf"], "a malformed allOf value")
	requireOpaque(t, canonical["required"], "a malformed required value")
	requireOpaque(t, cast[map[string]any](t, canonical["dependentRequired"])["trigger"], "a malformed dependent value")

	// A non-string entry inside a well-formed name array is opaque too.
	entries := cast[[]any](t, schemaview.Canonicalize(map[string]any{
		"required": []any{"Cache_Region", opaquePayload()},
	})["required"])
	if entries[0] != "cacheregion" {
		t.Fatalf("string entries still canonicalize: %v", entries)
	}
	requireOpaque(t, entries[1], "a non-string required entry")
}

func TestCanonicalizeDeepCopiesMalformedReferences(t *testing.T) {
	t.Parallel()
	// A non-string "$ref" is not a pointer, so it is ordinary opaque content: it
	// must be deep-copied with its authored keys intact rather than aliased, or
	// mutating the canonical copy would reach back into the source document.
	source := opaquePayload()
	cloned := schemaview.CanonicalizeReference(source)
	requireOpaque(t, cloned, "a malformed object reference")
	clonedMap := cast[map[string]any](t, cloned)
	clonedMap["cacheRegion"] = "mutated"
	cast[map[string]any](t, clonedMap["patternProperties"])["^Deep_Key"] = "mutated"
	cast[[]any](t, clonedMap["list"])[1] = "mutated"
	requireOpaque(t, source, "the source after mutating its canonical reference copy")

	// An array-valued reference is opaque through every element too.
	list := cast[[]any](t, schemaview.CanonicalizeReference([]any{opaquePayload(), "scalar"}))
	requireOpaque(t, list[0], "a malformed array reference")
	if list[1] != "scalar" {
		t.Fatalf("a scalar entry of a malformed reference must survive: %v", list)
	}

	// A scalar malformed reference and a malformed pointer string are unchanged.
	if got := schemaview.CanonicalizeReference(float64(1)); got != float64(1) {
		t.Fatalf("a scalar reference is carried through: %v", got)
	}
	if got := schemaview.CanonicalizeReference("#/$defs/bad~2escape"); got != "#/$defs/bad~2escape" {
		t.Fatalf("a malformed pointer is carried through: %v", got)
	}
}

// aliasProbe places an opaque payload at every position [schemaview.Canonicalize]
// passes through rather than rewrites, at the root and below a schema edge, so a
// surviving alias anywhere in that set is observable.
func aliasProbe() map[string]any {
	return map[string]any{
		"$ref":              opaquePayload(),
		"properties":        []any{opaquePayload()},
		"dependentSchemas":  "not-an-object",
		"dependentRequired": map[string]any{"trigger": opaquePayload()},
		"required":          []any{"Cache_Region", opaquePayload()},
		"const":             map[string]any{"Cache_Region": []any{map[string]any{"Deep-Key": "v"}}},
		"enum":              []any{map[string]any{"Data_Dir": "/var"}},
		"$defs":             map[string]any{"Body": map[string]any{"$ref": []any{opaquePayload()}}},
		"definitions":       "not-an-object",
		"not":               map[string]any{"$ref": opaquePayload(), "default": opaquePayload()},
		"allOf":             []any{map[string]any{"$ref": opaquePayload()}, true},
		"x-vendor":          opaquePayload(),
		"title":             "kept",
	}
}

// scramble overwrites every map value and slice element reachable from value, at
// every depth, so any alias back into the source document becomes visible.
func scramble(value any) {
	switch node := value.(type) {
	case map[string]any:
		for name, child := range node {
			scramble(child)
			node[name] = "scrambled"
		}
	case []any:
		for index, item := range node {
			scramble(item)
			node[index] = "scrambled"
		}
	default:
		// A scalar holds nothing that could alias the source.
	}
}

func TestCanonicalizeNeverAliasesTheSourceDocument(t *testing.T) {
	t.Parallel()
	// Canonicalize documents a DEEP COPY, so scrambling every position of the
	// canonical document must leave the source byte-for-byte as authored.
	source := aliasProbe()
	scramble(schemaview.Canonicalize(source))
	if !reflect.DeepEqual(source, aliasProbe()) {
		t.Fatalf("canonicalizing must deep copy every pass-through position: %v", source)
	}

	// The instance side carries the same contract.
	instance := map[string]any{"Nested": map[string]any{"Deep-Key": []any{map[string]any{"Inner_Key": "v"}}}}
	scramble(schemaview.CanonicalizeInstance(instance))
	if !reflect.DeepEqual(instance, map[string]any{
		"Nested": map[string]any{"Deep-Key": []any{map[string]any{"Inner_Key": "v"}}},
	}) {
		t.Fatalf("canonicalizing an instance must deep copy it: %v", instance)
	}
}

func TestCanonicalizeStillRewritesComparedData(t *testing.T) {
	t.Parallel()
	// const and enum ARE compared against instance keys, so they still
	// canonicalize even though every other non-schema value does not.
	canonical := schemaview.Canonicalize(map[string]any{
		"const": map[string]any{"Cache_Region": "v"},
		"enum":  []any{map[string]any{"Data_Dir": "/var"}},
	})
	constant := cast[map[string]any](t, canonical["const"])
	if _, present := constant["cacheregion"]; !present {
		t.Fatalf("const keys must still canonicalize: %v", constant)
	}
	alternative := cast[map[string]any](t, cast[[]any](t, canonical["enum"])[0])
	if _, present := alternative["datadir"]; !present {
		t.Fatalf("enum keys must still canonicalize: %v", alternative)
	}
	instance := schemaview.CanonicalizeInstance(map[string]any{"Cache_Region": "v"})
	if _, present := instance["cacheregion"]; !present {
		t.Fatalf("instance keys must still canonicalize: %v", instance)
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
