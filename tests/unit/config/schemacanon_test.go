package config_test

import (
	"context"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

// refBlock is a draft-2020-12 block that routes its object shape through $defs
// and a local $ref, with additionalProperties:false so a mis-spelled key is only
// accepted when alignment actually followed the reference.
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
		// ComposeSchema mounts the block under properties/<key>, so a local pointer
		// is written against the composed document root.
		"$ref": "#/properties/" + testhelper.DemoBlockKey + "/$defs/body",
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
	if err == nil {
		t.Fatal("a typed-container canonical collision must be rejected")
	}
	if _, isValidation := config.ValidationIssues(err); isValidation {
		t.Fatalf("a schema authoring fault is not a validation problem: %v", err)
	}
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
	if err == nil {
		t.Fatal("a canonical collision inside $defs must be rejected")
	}
	if _, isValidation := config.ValidationIssues(err); isValidation {
		t.Fatalf("a schema authoring fault is not a validation problem: %v", err)
	}
}

func TestSchemaValidateRejectsCrossCompositionCollision(t *testing.T) {
	t.Parallel()
	block := config.NewBlock(testhelper.DemoBlockKey, true, map[string]any{
		"type": "object",
		"allOf": []any{
			map[string]any{"properties": map[string]any{"cache_region": map[string]any{"type": "string"}}},
			map[string]any{"properties": map[string]any{"cacheRegion": map[string]any{"type": "string"}}},
		},
	})
	err := config.ComposeSchema(config.AppBlockSchema(), block).Validate(testhelper.ValidRaw())
	if err == nil {
		t.Fatal("a canonical collision across composed branches must be rejected")
	}
	if _, isValidation := config.ValidationIssues(err); isValidation {
		t.Fatalf("a schema authoring fault is not a validation problem: %v", err)
	}
}

func TestLoadAlignsThroughLocalRef(t *testing.T) {
	t.Parallel()
	// The base document spells the key in camel case while the schema declares it
	// in snake case behind $defs + $ref; the load only succeeds if the loader
	// aligned through the reference.
	base := testhelper.SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
demo:
  cacheRegion: east
`
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(base)),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema(), refBlock())),
	).Load(context.Background())
	loaded := testhelper.RequireConfig(t, cfg, err)

	var region string
	if decodeErr := loaded.Decode("demo.cacheRegion", &region); decodeErr != nil || region != "east" {
		t.Fatalf("value behind a local $ref must decode: %q %v", region, decodeErr)
	}
}

func TestLoadAlignsThroughComposition(t *testing.T) {
	t.Parallel()
	base := testhelper.SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
demo:
  cacheRegion: east
  data-dir: /var/lib
`
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(base)),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema(), composedBlock())),
	).Load(context.Background())
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
		// ComposeSchema mounts the block under properties/<key>, so a local pointer
		// is written against the composed document root.
		"$ref": "#/properties/" + testhelper.DemoBlockKey + "/$defs/body",
	})
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema(), block)),
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	if _, isValidation := config.ValidationIssues(loadErr); isValidation {
		t.Fatalf("a schema authoring fault is not a validation problem: %v", loadErr)
	}
}
