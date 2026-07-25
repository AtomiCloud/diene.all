package config_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	problemtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
)

const exampleBase = `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
`

// ExampleLoader shows the base-then-environment layering with a required schema:
// the base document sets full defaults and the environment layer, applied last,
// wins.
func ExampleLoader() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase))),
		config.WithEnvSource(config.NewMapEnvSource("env", map[string]string{
			"ATOMI_APP__VERSION": "2.0.0",
		})),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
	)
	cfg, err := loader.Load(context.Background())
	if err != nil {
		fmt.Println(err)
		return
	}
	app, _ := cfg.App()
	fmt.Println(app.Landscape, app.Version)
	// Output: base 2.0.0
}

// ExampleLoader_overlay shows a sparse per-landscape overlay overriding the base.
func ExampleLoader_overlay() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase))),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", config.NewBytesYAMLSource("overlay", []byte("app:\n  version: 3.0.0\n"))),
		config.WithEnvSource(config.NewMapEnvSource("env", nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
		config.WithErrorPortal(problemtest.SampleErrorPortal()),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Version)
	// Output: 3.0.0
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

// ExampleFragmentFromType shows deriving a composable fragment from a Go type.
func ExampleFragmentFromType() {
	fragment, _ := config.FragmentFromType(config.AppBlock{})
	fmt.Println(fragment["type"])
	// Output: object
}

// ExampleSchemaFromJSON shows loading a committed schema artifact and validating
// against the exact schema a service ships.
func ExampleSchemaFromJSON() {
	artifact, _ := config.ComposeSchema(config.AppBlockSchema()).Marshal()
	schema, _ := config.SchemaFromJSON(artifact)
	fmt.Println(schema.Root()["type"])
	// Output: object
}

// ExampleSchema_Marshal shows serializing the composed schema for the committed
// artifact.
func ExampleSchema_Marshal() {
	artifact, _ := config.ComposeSchema(config.AppBlockSchema()).Marshal()
	fmt.Println(strings.HasPrefix(string(artifact), "{"))
	// Output: true
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

// ExampleSchema_WithPortal shows binding a service-tree portal so validation
// problems mint their type URI from that identity.
func ExampleSchema_WithPortal() {
	schema := config.ComposeSchema(config.AppBlockSchema()).WithPortal(problemtest.SampleErrorPortal())
	err := schema.Validate(map[string]any{})
	issues, ok := config.ValidationIssues(err)
	fmt.Println(ok, len(issues) > 0)
	// Output: true true
}

// ExampleValidationIssues shows recovering readable issues from a load failure.
func ExampleValidationIssues() {
	err := config.ComposeSchema(config.AppBlockSchema()).Validate(map[string]any{})
	issues, ok := config.ValidationIssues(err)
	fmt.Println(ok, issues[0].String() != "")
	// Output: true true
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

// ExampleConfig_Raw shows reading the merged tree as an independent clone.
func ExampleConfig_Raw() {
	cfg := config.NewConfig(map[string]any{"app": map[string]any{"service": "config"}})
	fmt.Println(cfg.Raw()["app"])
	// Output: map[service:config]
}

// ExampleNewFileYAMLSource shows a filesystem-backed base layer.
func ExampleNewFileYAMLSource() {
	dir, _ := os.MkdirTemp("", "config-example")
	defer func() { _ = os.RemoveAll(dir) }()
	path := filepath.Join(dir, "settings.yaml")
	_ = os.WriteFile(path, []byte(exampleBase), 0o600)

	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewFileYAMLSource("base", path)),
		config.WithEnvSource(config.NewOSEnvSource()),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Platform)
	// Output: sulfoxide
}

// ExampleNewOptionalFileYAMLSource shows an absent optional layer resolving to no
// document rather than an error.
func ExampleNewOptionalFileYAMLSource() {
	source := config.NewOptionalFileYAMLSource("overlay", filepath.Join(os.TempDir(), "config-example-absent.yaml"))
	content, err := source.Read(context.Background())
	fmt.Println(content == nil, err)
	// Output: true <nil>
}
