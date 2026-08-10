package config_test

import (
	"context"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

// refBlock routes its object shape through $defs and an ORDINARY fragment-local
// pointer. Each block is mounted as its own schema resource, so the pointer
// resolves inside the block and the fragment stays portable.
func refBlock() config.Block {
	return config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"$defs": map[string]any{
			"body": map[string]any{
				"type":                 "object",
				"properties":           map[string]any{"cache_region": map[string]any{"type": "string"}},
				"required":             []any{"cache_region"},
				"additionalProperties": false,
			},
		},
		"$ref": "#/$defs/body",
	})
}

// composedBlock spreads one object across two allOf branches.
func composedBlock() config.Block {
	return config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"type": "object",
		"allOf": []any{
			map[string]any{"properties": map[string]any{"cache_region": map[string]any{"type": "string"}}},
			map[string]any{"properties": map[string]any{"data_dir": map[string]any{"type": "string"}}},
		},
		"required": []any{"cache_region", "data_dir"},
	})
}

// demoBase renders a base document whose demo block is body.
func demoBase(body string) string {
	return testhelper.SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
demo:
` + body
}

// loadDemo runs a full three-layer load of block against a demo body.
func loadDemo(t *testing.T, block config.Block, body string) (*config.Config, error) {
	t.Helper()
	return config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(demoBase(body))),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema(), block)),
	).Load(context.Background())
}

// requireAuthoringFault asserts err is a plain authoring fault, never a
// problem-typed validation failure.
func requireAuthoringFault(t *testing.T, err error, what string) {
	t.Helper()
	if err == nil {
		t.Fatalf("%s must be rejected", what)
	}
	if _, isValidation := config.ValidationIssues(err); isValidation {
		t.Fatalf("%s is an authoring fault, not a validation problem: %v", what, err)
	}
}

func TestSchemaValidateRejectsTypedPropertiesCollision(t *testing.T) {
	t.Parallel()
	// A NewBlock fragment authored with typed Go containers is legal; its
	// canonical collision must still be rejected through the public surface.
	block := config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"type": "object",
		"properties": map[string]map[string]any{
			"cache_region": {"type": "string"},
			"cacheRegion":  {"type": "string"},
		},
	})
	err := config.ComposeSchema(config.AppBlockSchema(), block).Validate(testhelper.ValidRaw())
	requireAuthoringFault(t, err, "a typed-container canonical collision")
}

func TestSchemaValidateRejectsCollisionInsideDefs(t *testing.T) {
	t.Parallel()
	block := config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"type": "object",
		"$defs": map[string]any{
			"body": map[string]any{"properties": map[string]any{
				"data-dir": map[string]any{"type": "string"},
				"dataDir":  map[string]any{"type": "string"},
			}},
		},
	})
	err := config.ComposeSchema(config.AppBlockSchema(), block).Validate(testhelper.ValidRaw())
	requireAuthoringFault(t, err, "a canonical collision inside $defs")
}

func TestSchemaValidateAcceptsCrossBranchCanonicalTwins(t *testing.T) {
	t.Parallel()
	// Two branches spelling one logical key differently are NOT ambiguous: under
	// the canonical relation they name the same key, and the compiler applies each
	// branch's constraints natively. Both allOf constraints must therefore bind.
	block := config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"type": "object",
		"allOf": []any{
			map[string]any{"properties": map[string]any{"cache_region": map[string]any{"type": "string"}}},
			map[string]any{"properties": map[string]any{"cacheRegion": map[string]any{"minLength": float64(3)}}},
		},
	})
	schema := config.ComposeSchema(config.AppBlockSchema(), block)

	valid := testhelper.ValidRaw()
	valid[testhelper.DemoBlockKey] = map[string]any{"cache-region": "east"}
	if err := schema.Validate(valid); err != nil {
		t.Fatalf("cross-branch canonical twins must compose, not reject: %v", err)
	}

	// The SECOND branch's constraint still binds through a third spelling.
	short := testhelper.ValidRaw()
	short[testhelper.DemoBlockKey] = map[string]any{"CacheRegion": "ab"}
	if _, isValidation := config.ValidationIssues(schema.Validate(short)); !isValidation {
		t.Fatal("both composed branches must constrain the one canonical key")
	}

	// The FIRST branch's type constraint binds too.
	wrongType := testhelper.ValidRaw()
	wrongType[testhelper.DemoBlockKey] = map[string]any{"cacheRegion": float64(1)}
	if _, isValidation := config.ValidationIssues(schema.Validate(wrongType)); !isValidation {
		t.Fatal("the first composed branch must constrain the one canonical key")
	}
}

func TestLoadValidatesThroughBlockLocalRef(t *testing.T) {
	t.Parallel()
	// The base spells the key in camel case while the schema declares it in snake
	// case behind an ordinary fragment-local pointer.
	cfg, err := loadDemo(t, refBlock(), "  cacheRegion: east\n")
	loaded := testhelper.RequireConfig(t, cfg, err)

	var region string
	if decodeErr := loaded.Decode("demo.cacheRegion", &region); decodeErr != nil || region != "east" {
		t.Fatalf("value behind a block-local $ref must decode: %q %v", region, decodeErr)
	}
}

func TestLoadValidatesThroughComposition(t *testing.T) {
	t.Parallel()
	cfg, err := loadDemo(t, composedBlock(), "  cacheRegion: east\n  data-dir: /var/lib\n")
	loaded := testhelper.RequireConfig(t, cfg, err)

	var dataDir string
	if decodeErr := loaded.Decode("demo.dataDir", &dataDir); decodeErr != nil || dataDir != "/var/lib" {
		t.Fatalf("value spread across allOf branches must decode: %q %v", dataDir, decodeErr)
	}
}

func TestLoadRejectsSchemaCollisionThroughLoader(t *testing.T) {
	t.Parallel()
	block := config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"type": "object",
		"$defs": map[string]any{
			"body": map[string]any{"properties": map[string]any{
				"a-b": map[string]any{"type": "string"},
				"aB":  map[string]any{"type": "string"},
			}},
		},
		"$ref": "#/$defs/body",
	})
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema(), block)),
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	requireAuthoringFault(t, loadErr, "a schema collision reached through the loader")
}
