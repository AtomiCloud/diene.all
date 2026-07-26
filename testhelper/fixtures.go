package testhelper

import "github.com/AtomiCloud/diene.go-config/lib/config"

// DemoBlockKey is the root key of the neutral demo block. config never owns an
// engine's block, so fixtures compose against this synthetic block instead of a
// real otel or auth-engine schema.
const DemoBlockKey = "demo"

// SchemaPointer is the first-line schema reference every fixture and committed
// sample YAML declares.
const SchemaPointer = "# yaml-language-server: $schema=./config.schema.json"

// DemoBlock returns a synthetic, engine-neutral [config.Block]: a required
// region string, an integer replica list, and an optional secret. It stands in
// for the engine blocks a real service would compose.
func DemoBlock() config.Block {
	return config.NewBlock(DemoBlockKey, true, map[string]any{
		"type": "object",
		"properties": map[string]any{
			"region":   map[string]any{"type": "string", "minLength": float64(1)},
			"replicas": map[string]any{"type": "array", "items": map[string]any{"type": "integer"}},
			"secret":   map[string]any{"type": "string"},
		},
		"required":             []any{"region"},
		"additionalProperties": true,
	})
}

// Schema composes the config-owned app block with the neutral [DemoBlock].
func Schema() config.Schema {
	return config.ComposeSchema(config.AppBlockSchema(), DemoBlock())
}

// InvalidSchemaBlock returns a block whose fragment cannot compile — it
// references a definition that does not exist — so consumers can exercise the
// schema-authoring fault path.
func InvalidSchemaBlock() config.Block {
	return config.NewBlock("broken", true, map[string]any{"$ref": "#/$defs/missing"})
}

// BaseDocument is a valid base YAML document with full defaults, a complete app
// block whose landscape is the no-overlay sentinel, and a blank secret example.
func BaseDocument() string {
	return SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 0.0.0
demo:
  region: local
  replicas:
    - 1
    - 2
  secret: ""
`
}

// OverlayDocument is a sparse overlay for landscape: it overrides only the app
// landscape and the demo region, inheriting every other value from the base.
func OverlayDocument(landscape string) string {
	return SchemaPointer + `
app:
  landscape: ` + landscape + `
demo:
  region: ap-southeast-1
`
}

// InvalidOverlayDocument is a sparse overlay whose merged result violates the
// schema: it blanks the app version, which the app block requires to be
// non-empty. It drives the fail-fast red test.
func InvalidOverlayDocument() string {
	return SchemaPointer + `
app:
  version: ""
`
}

// ValidRaw returns an already-merged, schema-valid configuration map for
// building stubs.
func ValidRaw() map[string]any {
	return map[string]any{
		"app": map[string]any{
			"landscape": "lapras",
			"platform":  "sulfoxide",
			"service":   "config",
			"module":    "lib",
			"version":   "1.0.0",
		},
		"demo": map[string]any{
			"region":   "ap-southeast-1",
			"replicas": []any{1, 2},
			"secret":   "",
		},
	}
}

// StubConfig wraps raw as a [config.Config] WITHOUT validating it. It is an
// unchecked stub for decode/accessor tests; the caller is responsible for the
// map's validity. Use [ValidRaw] for a map proven to satisfy [Schema], or run
// the real loader when validation matters.
func StubConfig(raw map[string]any) *config.Config {
	return config.NewConfig(raw)
}

// StubApp builds an unchecked [config.Config] carrying only app as its
// service-tree block. It is not validated against any schema — it exists so
// App-block accessor tests need not spell out a full document.
func StubApp(app config.AppBlock) *config.Config {
	return config.NewConfig(map[string]any{
		"app": map[string]any{
			"landscape": app.Landscape,
			"platform":  app.Platform,
			"service":   app.Service,
			"module":    app.Module,
			"version":   app.Version,
		},
	})
}
