package config_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

// demoSchema composes the app block with a demo block carrying fragment.
func demoSchema(fragment map[string]any) config.Schema {
	return config.ComposeSchema(
		config.AppBlockSchema(),
		config.NewBlock(testhelper.DemoBlockKey, true, fragment),
	)
}

// withDemo returns a schema-valid instance whose demo block is body.
func withDemo(body map[string]any) map[string]any {
	instance := testhelper.ValidRaw()
	instance[testhelper.DemoBlockKey] = body
	return instance
}

// requireValidationProblem asserts err is a problem-typed validation failure.
func requireValidationProblem(t *testing.T, err error, what string) []config.Issue {
	t.Helper()
	issues, isValidation := config.ValidationIssues(err)
	if !isValidation {
		t.Fatalf("%s must be a validation problem, got: %v", what, err)
	}
	return issues
}

func TestNegatedBranchNamesAreConstrained(t *testing.T) {
	t.Parallel()
	// The ONLY declaration of the key is inside a negated branch, so no
	// "accepted spelling" view could ever learn it. Canonicalizing both sides
	// makes the negation bind for every spelling Decode treats as the same key.
	schema := demoSchema(map[string]any{
		"type": "object",
		"not": map[string]any{
			"type":       "object",
			"properties": map[string]any{"danger_mode": map[string]any{"const": true}},
			"required":   []any{"danger_mode"},
		},
	})

	for _, spelling := range []string{"danger_mode", "dangerMode", "DangerMode", "danger-mode"} {
		t.Run("rejects "+spelling, func(t *testing.T) {
			t.Parallel()
			requireValidationProblem(t,
				schema.Validate(withDemo(map[string]any{spelling: true})),
				"a negated branch violated as "+spelling)
		})
	}

	// Negative control: the negated branch does not match, so the document is fine.
	if err := schema.Validate(withDemo(map[string]any{"dangerMode": false})); err != nil {
		t.Fatalf("a document the negated branch does not match must be accepted: %v", err)
	}
}

func TestNegatedBranchBindsThroughLoaderAndAgreesWithDecode(t *testing.T) {
	t.Parallel()
	fragment := map[string]any{
		"type": "object",
		"not": map[string]any{
			"type":       "object",
			"properties": map[string]any{"danger_mode": map[string]any{"const": true}},
			"required":   []any{"danger_mode"},
		},
	}
	block := config.NewBlock(testhelper.DemoBlockKey, true, fragment)

	cfg, err := loadDemo(t, block, "  dangerMode: true\n")
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	requireValidationProblem(t, loadErr, "a negated branch violated through the loader")

	// Decode agreement: the spelling the loader would have exposed under the
	// schema's own name is exactly the spelling validation constrained.
	accepted, acceptErr := loadDemo(t, block, "  dangerMode: false\n")
	loaded := testhelper.RequireConfig(t, accepted, acceptErr)
	var mode bool
	if decodeErr := loaded.Decode("demo.danger_mode", &mode); decodeErr != nil || mode {
		t.Fatalf("Decode must resolve the schema's spelling of the same key: %v %v", mode, decodeErr)
	}
}

func TestSpellingInsensitiveKeywordMatrix(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name     string
		fragment map[string]any
		accepted map[string]any
		rejected map[string]any
	}{
		{
			name: "required only name",
			fragment: map[string]any{
				"type":     "object",
				"required": []any{"cache_region"},
			},
			accepted: map[string]any{"cacheRegion": "east"},
			rejected: map[string]any{"other": "x"},
		},
		{
			name: "dependentRequired trigger and dependent aliases",
			fragment: map[string]any{
				"type":              "object",
				"dependentRequired": map[string]any{"cache_region": []any{"data_dir"}},
			},
			// The trigger is spelled differently AND the dependent is satisfied by
			// yet another spelling.
			accepted: map[string]any{"cacheRegion": "east", "DataDir": "/var"},
			// The trigger alias must still ARM the dependency (the old fail-open).
			rejected: map[string]any{"cacheRegion": "east"},
		},
		{
			name: "contains",
			fragment: map[string]any{
				"type": "object",
				"properties": map[string]any{"list": map[string]any{
					"type": "array",
					"contains": map[string]any{
						"type":       "object",
						"properties": map[string]any{"marked_item": map[string]any{"const": true}},
						"required":   []any{"marked_item"},
					},
				}},
				"required": []any{"list"},
			},
			accepted: map[string]any{"list": []any{map[string]any{"markedItem": true}}},
			rejected: map[string]any{"list": []any{map[string]any{"markedItem": false}}},
		},
		{
			name: "unevaluatedProperties across a composed branch",
			fragment: map[string]any{
				"type":                  "object",
				"allOf":                 []any{map[string]any{"properties": map[string]any{"cache_region": map[string]any{"type": "string"}}}},
				"unevaluatedProperties": false,
			},
			accepted: map[string]any{"cacheRegion": "east"},
			rejected: map[string]any{"cacheRegion": "east", "undeclared": "x"},
		},
		{
			name: "unevaluatedItems over prefixItems",
			fragment: map[string]any{
				"type": "object",
				"properties": map[string]any{"tuple": map[string]any{
					"type":             "array",
					"prefixItems":      []any{map[string]any{"type": "object", "properties": map[string]any{"first_key": map[string]any{"type": "string"}}, "required": []any{"first_key"}}},
					"unevaluatedItems": false,
				}},
			},
			accepted: map[string]any{"tuple": []any{map[string]any{"firstKey": "a"}}},
			rejected: map[string]any{"tuple": []any{map[string]any{"firstKey": "a"}, "extra"}},
		},
		{
			name: "object const equality across spellings",
			fragment: map[string]any{
				"type": "object",
				"properties": map[string]any{"pinned": map[string]any{
					"const": map[string]any{"cache_region": "east"},
				}},
				"required": []any{"pinned"},
			},
			accepted: map[string]any{"pinned": map[string]any{"cacheRegion": "east"}},
			rejected: map[string]any{"pinned": map[string]any{"cacheRegion": "west"}},
		},
		{
			name: "object enum equality across spellings and equivalent alternatives",
			fragment: map[string]any{
				"type": "object",
				"properties": map[string]any{"choice": map[string]any{
					"enum": []any{
						map[string]any{"data_dir": "/var"},
						// Canonically equivalent to the first alternative.
						map[string]any{"dataDir": "/var"},
						map[string]any{"data_dir": "/opt"},
					},
				}},
				"required": []any{"choice"},
			},
			accepted: map[string]any{"choice": map[string]any{"DataDir": "/opt"}},
			rejected: map[string]any{"choice": map[string]any{"DataDir": "/nope"}},
		},
		{
			name: "then branch selected natively",
			fragment: map[string]any{
				"type":     "object",
				"if":       map[string]any{"properties": map[string]any{"mode": map[string]any{"const": "strict"}}, "required": []any{"mode"}},
				"then":     map[string]any{"required": []any{"cache_region"}},
				"else":     map[string]any{"required": []any{"data_dir"}},
				"required": []any{"mode"},
			},
			accepted: map[string]any{"mode": "strict", "cacheRegion": "east"},
			rejected: map[string]any{"mode": "strict", "dataDir": "/var"},
		},
		{
			name: "else branch selected natively",
			fragment: map[string]any{
				"type":     "object",
				"if":       map[string]any{"properties": map[string]any{"mode": map[string]any{"const": "strict"}}, "required": []any{"mode"}},
				"then":     map[string]any{"required": []any{"cache_region"}},
				"else":     map[string]any{"required": []any{"data_dir"}},
				"required": []any{"mode"},
			},
			accepted: map[string]any{"mode": "loose", "DataDir": "/var"},
			rejected: map[string]any{"mode": "loose", "CacheRegion": "east"},
		},
		{
			name: "discriminated oneOf",
			fragment: map[string]any{
				"type": "object",
				"oneOf": []any{
					map[string]any{
						"properties": map[string]any{"kind": map[string]any{"const": "cache"}, "cache_region": map[string]any{"type": "string"}},
						"required":   []any{"kind", "cache_region"},
					},
					map[string]any{
						"properties": map[string]any{"kind": map[string]any{"const": "disk"}, "data_dir": map[string]any{"type": "string"}},
						"required":   []any{"kind", "data_dir"},
					},
				},
			},
			// The discriminator picks exactly one branch, so an aliased spelling of
			// that branch's own key satisfies it.
			accepted: map[string]any{"kind": "disk", "DataDir": "/var"},
			// Matches neither branch: the discriminator names a third kind.
			rejected: map[string]any{"kind": "other", "DataDir": "/var"},
		},
		{
			name: "dedupes canonically equal required entries",
			fragment: map[string]any{
				"type":     "object",
				"required": []any{"cache_region", "cacheRegion", "CACHE-REGION"},
			},
			accepted: map[string]any{"CacheRegion": "east"},
			rejected: map[string]any{"other": "x"},
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			schema := demoSchema(testCase.fragment)
			if err := schema.Validate(withDemo(testCase.accepted)); err != nil {
				t.Fatalf("accepted instance must validate: %v", err)
			}
			requireValidationProblem(t, schema.Validate(withDemo(testCase.rejected)), "the rejected instance")
		})
	}
}

func TestCanonicalSchemaMatchesManuallyCanonicalSchema(t *testing.T) {
	t.Parallel()
	// Equivalence, not merely acceptance: an aliased schema must behave exactly
	// like the schema an author would have written in canonical spelling.
	aliased := demoSchema(map[string]any{
		"type": "object",
		"allOf": []any{
			map[string]any{"properties": map[string]any{"cache_region": map[string]any{"type": "string"}}},
			map[string]any{"properties": map[string]any{"cacheRegion": map[string]any{"minLength": float64(3)}}},
		},
		"required": []any{"cache-region"},
	})
	manual := demoSchema(map[string]any{
		"type":       "object",
		"properties": map[string]any{"cacheregion": map[string]any{"type": "string", "minLength": float64(3)}},
		"required":   []any{"cacheregion"},
	})

	for _, body := range []map[string]any{
		{"cacheRegion": "east"},
		{"cacheRegion": "ab"},
		{"cacheRegion": float64(1)},
		{"other": "x"},
	} {
		_, aliasedIsProblem := config.ValidationIssues(aliased.Validate(withDemo(body)))
		_, manualIsProblem := config.ValidationIssues(manual.Validate(withDemo(body)))
		if aliasedIsProblem != manualIsProblem {
			t.Fatalf("aliased and manually canonical schemas disagree on %v: %v vs %v", body, aliasedIsProblem, manualIsProblem)
		}
	}
}

func TestValidationPathKeepsAuthoredSpelling(t *testing.T) {
	t.Parallel()
	schema := demoSchema(map[string]any{
		"type":       "object",
		"properties": map[string]any{"cache_region": map[string]any{"type": "string"}},
	})
	// The instance spells the key its own way; the reported path must echo THAT
	// spelling, not the canonical form the compiler evaluated.
	issues := requireValidationProblem(t,
		schema.Validate(withDemo(map[string]any{"cacheRegion": float64(1)})),
		"a type mismatch")

	paths := make([]string, 0, len(issues))
	for _, issue := range issues {
		paths = append(paths, issue.Path)
	}
	if !slices.Contains(paths, "demo.cacheRegion") {
		t.Fatalf("path must keep the authored spelling, got %v", paths)
	}
}

func TestValidationPathThroughArrayKeepsAuthoredSpelling(t *testing.T) {
	t.Parallel()
	schema := demoSchema(map[string]any{
		"type": "object",
		"properties": map[string]any{"list": map[string]any{
			"type":  "array",
			"items": map[string]any{"type": "object", "properties": map[string]any{"item_key": map[string]any{"type": "string"}}},
		}},
	})
	issues := requireValidationProblem(t,
		schema.Validate(withDemo(map[string]any{"list": []any{map[string]any{"itemKey": float64(1)}}})),
		"a type mismatch inside an array")

	paths := make([]string, 0, len(issues))
	for _, issue := range issues {
		paths = append(paths, issue.Path)
	}
	if !slices.Contains(paths, "demo.list.0.itemKey") {
		t.Fatalf("array path must keep the authored spelling, got %v", paths)
	}
}

func TestUnsupportedSchemaConstructsAreAuthoringFaults(t *testing.T) {
	t.Parallel()
	cases := map[string]map[string]any{
		"patternProperties": {"patternProperties": map[string]any{"^x": map[string]any{"type": "string"}}},
		"propertyNames":     {"propertyNames": map[string]any{"minLength": float64(2)}},
		"$anchor":           {"$anchor": "here"},
		"$dynamicAnchor":    {"$dynamicAnchor": "node"},
		"$dynamicRef":       {"$dynamicRef": "#node"},
		"$recursiveAnchor":  {"$recursiveAnchor": true},
		"$recursiveRef":     {"$recursiveRef": "#"},
		"$vocabulary":       {"$vocabulary": map[string]any{"https://example.invalid/v": true}},
		"dependencies":      {"dependencies": map[string]any{"a": []any{"b"}}},
		"additionalItems":   {"additionalItems": map[string]any{"type": "string"}},
		"contentSchema":     {"contentSchema": map[string]any{"type": "object"}},
		"contentEncoding":   {"contentEncoding": "base64"},
		"contentMediaType":  {"contentMediaType": "application/json"},
		"nested $schema":    {"$schema": config.Draft2020},
		"authored $id":      {"$id": "https://example.invalid/mine.json"},
		"remote $ref":       {"$ref": "https://example.invalid/other.json"},
		"anchor $ref":       {"$ref": "#node"},
		"percent $ref":      {"$ref": "#/%24defs/body"},
		"malformed escape":  {"$defs": map[string]any{"body": map[string]any{"type": "object"}}, "$ref": "#/$defs/bo~2dy"},
		"dangling $ref":     {"$ref": "#/$defs/missing"},
	}
	for name, fragment := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			err := demoSchema(fragment).Validate(testhelper.ValidRaw())
			requireAuthoringFault(t, err, "the unsupported construct "+name)
		})
	}
}

func TestLookalikeKeysInsideDataAreNotDenied(t *testing.T) {
	t.Parallel()
	// Every denied word appears here as DATA, not as a schema keyword. Data is
	// opaque, so none of it may be denied.
	lookalike := map[string]any{
		"$ref":              "https://example.invalid/other.json",
		"$id":               "https://example.invalid/mine.json",
		"$anchor":           "here",
		"$dynamicRef":       "#node",
		"$recursiveRef":     "#",
		"patternProperties": map[string]any{"^x": true},
		"propertyNames":     map[string]any{"minLength": float64(2)},
		"dependencies":      map[string]any{"a": []any{"b"}},
		"contentSchema":     map[string]any{"type": "object"},
	}
	schema := demoSchema(map[string]any{
		"type": "object",
		"properties": map[string]any{
			"pinned":  map[string]any{"const": lookalike},
			"choice":  map[string]any{"enum": []any{lookalike}},
			"sample":  map[string]any{"default": lookalike, "examples": []any{lookalike}},
			"unknown": map[string]any{"x-vendor": lookalike},
		},
	})
	if err := schema.Validate(withDemo(map[string]any{"pinned": lookalike})); err != nil {
		t.Fatalf("keyword-lookalike DATA must stay opaque: %v", err)
	}
}

func TestReferenceGrammarThroughPublicSurface(t *testing.T) {
	t.Parallel()
	accepted := map[string]map[string]any{
		"escaped tokens": {
			"$defs": map[string]any{"a/b~c": map[string]any{"type": "object"}},
			"$ref":  "#/$defs/a~1b~0c",
		},
		"boolean $defs entry": {
			"$defs": map[string]any{"anything": true},
			"$ref":  "#/$defs/anything",
		},
		"pointer through a canonicalized property token": {
			"$defs": map[string]any{"body": map[string]any{
				"type":       "object",
				"properties": map[string]any{"cache_region": map[string]any{"type": "object", "properties": map[string]any{"inner_key": map[string]any{"type": "string"}}}},
			}},
			"type":       "object",
			"properties": map[string]any{"echo": map[string]any{"$ref": "#/$defs/body/properties/cache_region"}},
		},
		"root pointer": {
			// "#" names the block resource root itself; here it types a nested
			// property, so the reference resolves without self-recursion.
			"type":       "object",
			"properties": map[string]any{"echo": map[string]any{"$ref": "#"}},
		},
	}
	for name, fragment := range accepted {
		t.Run("accepts "+name, func(t *testing.T) {
			t.Parallel()
			if err := demoSchema(fragment).Validate(withDemo(map[string]any{})); err != nil {
				t.Fatalf("%s must be supported: %v", name, err)
			}
		})
	}

	rejected := map[string]map[string]any{
		"keyword container target": {
			"$defs": map[string]any{"body": map[string]any{"type": "object"}},
			"$ref":  "#/$defs",
		},
		"target inside const data": {
			"type":       "object",
			"properties": map[string]any{"pinned": map[string]any{"const": map[string]any{"body": map[string]any{"type": "object"}}}},
			"$ref":       "#/properties/pinned/const/body",
		},
		"target inside enum data": {
			"type":       "object",
			"properties": map[string]any{"choice": map[string]any{"enum": []any{map[string]any{"body": map[string]any{"type": "object"}}}}},
			"$ref":       "#/properties/choice/enum/0/body",
		},
		"target inside an unknown annotation": {
			"type":     "object",
			"x-vendor": map[string]any{"body": map[string]any{"type": "object"}},
			"$ref":     "#/x-vendor/body",
		},
	}
	for name, fragment := range rejected {
		t.Run("rejects "+name, func(t *testing.T) {
			t.Parallel()
			requireAuthoringFault(t, demoSchema(fragment).Validate(testhelper.ValidRaw()), "a reference to "+name)
		})
	}
}

func TestCrossResourceReferenceIsRejected(t *testing.T) {
	t.Parallel()
	// One block may not reach into another, and the composed root may not declare
	// a reference at all.
	other := config.NewBlock("other", false, map[string]any{
		"$defs": map[string]any{"body": map[string]any{"type": "object"}},
		"type":  "object",
	})
	reaching := config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"$ref": "#/properties/other/$defs/body",
	})
	schema := config.ComposeSchema(config.AppBlockSchema(), other, reaching)
	requireAuthoringFault(t, schema.Validate(testhelper.ValidRaw()), "a cross-resource reference")
}

func TestSiblingCollisionsInOverwriteMaps(t *testing.T) {
	t.Parallel()
	cases := map[string]map[string]any{
		"properties": {"properties": map[string]any{
			"cache_region": map[string]any{"type": "string"},
			"cacheRegion":  map[string]any{"type": "string"},
		}},
		"dependentSchemas": {"dependentSchemas": map[string]any{
			"cache_region": map[string]any{"type": "object"},
			"cacheRegion":  map[string]any{"type": "object"},
		}},
		"dependentRequired triggers": {"dependentRequired": map[string]any{
			"cache_region": []any{"a"},
			"cacheRegion":  []any{"b"},
		}},
		"nested inside const": {"properties": map[string]any{"pinned": map[string]any{
			"const": map[string]any{"outer": map[string]any{"data_dir": "x", "dataDir": "y"}},
		}}},
		"nested inside an enum array": {"properties": map[string]any{"choice": map[string]any{
			"enum": []any{map[string]any{"list": []any{map[string]any{"a_b": 1, "aB": 2}}}},
		}}},
	}
	for name, fragment := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			requireAuthoringFault(t, demoSchema(fragment).Validate(testhelper.ValidRaw()), "sibling canonical twins in "+name)
		})
	}
}

func TestFragmentFromTypeMountsDirectly(t *testing.T) {
	t.Parallel()
	// The documented path: reflect a type, mount it, compose, validate — with no
	// manual removal of the reflector's root resource markers.
	fragment, err := config.FragmentFromType(struct {
		CacheRegion string `json:"cache_region"`
	}{})
	if err != nil {
		t.Fatalf("fragment: %v", err)
	}
	if _, present := fragment["$schema"]; present {
		t.Fatal("a mountable fragment must not carry the reflector's root $schema")
	}
	if _, present := fragment["$id"]; present {
		t.Fatal("a mountable fragment must not carry the reflector's root $id")
	}
	schema := config.ComposeSchema(config.AppBlockSchema(), config.NewBlock(testhelper.DemoBlockKey, true, fragment))
	if err = schema.Validate(withDemo(map[string]any{"cacheRegion": "east"})); err != nil {
		t.Fatalf("a reflected fragment must compose and validate directly: %v", err)
	}
}

func TestMarshalRoundTripKeepsPortableLocalRefs(t *testing.T) {
	t.Parallel()
	schema := config.ComposeSchema(config.AppBlockSchema(), refBlock())
	artifact, err := schema.Marshal()
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if !strings.Contains(string(artifact), `"$ref": "#/$defs/body"`) {
		t.Fatalf("the committed artifact must keep the authored local pointer: %s", artifact)
	}
	reloaded, err := config.SchemaFromJSON(artifact)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if err = reloaded.Validate(withDemo(map[string]any{"cacheRegion": "east"})); err != nil {
		t.Fatalf("a reloaded artifact must still resolve its block-local pointer: %v", err)
	}
}

func TestSchemaFromJSONRejectsArbitraryResourceIdentity(t *testing.T) {
	t.Parallel()
	// A hand-edited artifact whose block claims its own identity is an authoring
	// fault on the same path as any other unsupported construct.
	tampered := []byte(`{
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "properties": {"demo": {"$id": "https://example.invalid/mine.json", "type": "object"}},
      "additionalProperties": true
    }`)
	reloaded, err := config.SchemaFromJSON(tampered)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	requireAuthoringFault(t, reloaded.Validate(testhelper.ValidRaw()), "an arbitrary block resource identity")
}

func TestBlockKeysProduceValidUniqueResourceIdentities(t *testing.T) {
	t.Parallel()
	keys := []string{"demo", "a/b", "..", "ünïcode", "with space", "$weird"}
	seen := map[string]string{}
	for _, key := range keys {
		schema := config.ComposeSchema(config.NewBlock(key, false, map[string]any{"type": "object"}))
		mounted, ok := schema.Root()["properties"].(map[string]any)[key].(map[string]any)
		if !ok {
			t.Fatalf("block %q was not mounted", key)
		}
		identity, ok := mounted["$id"].(string)
		if !ok || !strings.HasPrefix(identity, "https://") || strings.ContainsAny(identity, " \"") {
			t.Fatalf("block %q produced an unusable resource identity %q", key, identity)
		}
		if other, taken := seen[identity]; taken {
			t.Fatalf("blocks %q and %q collide on resource identity %q", other, key, identity)
		}
		seen[identity] = key
	}
}

func TestBlockWithNoFragmentStillMountsAsAResource(t *testing.T) {
	t.Parallel()
	// A block may legitimately carry no fragment at all; it still needs its own
	// resource identity so the mount stays uniform.
	schema := config.ComposeSchema(config.NewBlock("demo", false, nil))
	mounted := cast[map[string]any](t, cast[map[string]any](t, schema.Root()["properties"])["demo"])
	identity, isString := mounted["$id"].(string)
	if !isString || !strings.HasPrefix(identity, "https://") {
		t.Fatalf("an empty block must still be mounted as its own resource: %v", mounted)
	}
	if err := schema.Validate(map[string]any{"demo": map[string]any{"anything": 1}}); err != nil {
		t.Fatalf("an empty block constrains nothing: %v", err)
	}
}

func TestUnencodableInstanceIsAnAuthoringFault(t *testing.T) {
	t.Parallel()
	err := demoSchema(map[string]any{"type": "object"}).Validate(map[string]any{"bad": make(chan int)})
	requireAuthoringFault(t, err, "an instance that cannot be encoded")
}

func TestAuthoredBlockIdentityIsNotOverwritten(t *testing.T) {
	t.Parallel()
	authored := "https://example.invalid/mine.json"
	schema := config.ComposeSchema(config.NewBlock("demo", false, map[string]any{"$id": authored, "type": "object"}))
	mounted, ok := schema.Root()["properties"].(map[string]any)["demo"].(map[string]any)
	if !ok || mounted["$id"] != authored {
		t.Fatalf("an authored identity must survive composition as evidence: %v", schema.Root())
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
