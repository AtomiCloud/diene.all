package config_test

import (
	"context"
	"fmt"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config"
)

// ExampleLoader shows the base-then-overlay-then-environment layering: the base
// document sets full defaults and the environment layer, applied last, wins.
func ExampleLoader() {
	base := config.NewBytesYAMLSource("base", []byte(`
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
`))
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(base),
		config.WithEnvSource(config.NewMapEnvSource("env", map[string]string{
			"ATOMI_APP__VERSION": "2.0.0",
		})),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Landscape, app.Version)
	// Output: base 2.0.0
}

// ExampleComposeSchema shows a service composing the config-owned app block into
// a root schema.
func ExampleComposeSchema() {
	schema := config.ComposeSchema(config.AppBlockSchema())
	fmt.Println(schema.Root()["type"], schema.Root()["$schema"])
	// Output: object https://json-schema.org/draft/2020-12/schema
}

// ExampleNewBlock shows an engine exporting its owned section for composition.
// config never defines the block; it only mounts and validates the fragment.
func ExampleNewBlock() {
	block := config.NewBlock("otel", true, map[string]any{"type": "object"})
	fmt.Println(block.Key, block.Required)
	// Output: otel true
}

// ExampleGenerateSchema shows reflecting a Go type into a JSON Schema fragment.
func ExampleGenerateSchema() {
	schema, _ := config.GenerateSchema(config.AppBlock{})
	fmt.Println(strings.Contains(string(schema), "landscape"))
	// Output: true
}

// ExampleSchemaFromJSON shows loading a committed schema artifact and validating
// against the exact schema a service ships.
func ExampleSchemaFromJSON() {
	artifact, _ := config.ComposeSchema(config.AppBlockSchema()).Marshal()
	schema, _ := config.SchemaFromJSON(artifact)
	fmt.Println(schema.Root()["type"])
	// Output: object
}

// ExampleSchema_Validate shows a validation failure surfacing as a problem-typed
// error whose readable issues name the offending field.
func ExampleSchema_Validate() {
	schema := config.ComposeSchema(config.AppBlockSchema())
	instance := map[string]any{"app": map[string]any{
		"landscape": "lapras", "platform": "sulfoxide",
		"service": "config", "module": "lib", "version": "",
	}}
	err := schema.Validate(instance)
	issues, _ := config.ValidationIssues(err)
	fmt.Println(issues[0].Path)
	// Output: app.version
}

// ExampleConfig_Decode shows the typed-slice serving surface decoding a validated
// subtree into a Go slice.
func ExampleConfig_Decode() {
	cfg := config.NewConfig(map[string]any{"demo": map[string]any{"replicas": []any{1, 2, 3}}})
	var replicas []int
	_ = cfg.Decode("demo.replicas", &replicas)
	fmt.Println(replicas)
	// Output: [1 2 3]
}

// ExampleConfig_App shows recovering the service-tree identity block.
func ExampleConfig_App() {
	cfg := config.NewConfig(map[string]any{"app": map[string]any{
		"landscape": "lapras", "platform": "sulfoxide",
		"service": "config", "module": "lib", "version": "1.0.0",
	}})
	app, _ := cfg.App()
	fmt.Println(app.Service)
	// Output: config
}
