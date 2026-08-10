package config_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// ExampleAppKey shows the root key the service-tree block is carried under.
func ExampleAppKey() {
	fmt.Println(config.AppKey)
	// Output: app
}

// ExampleDraft2020 shows the JSON Schema draft this package targets.
func ExampleDraft2020() {
	fmt.Println(config.Draft2020)
	// Output: https://json-schema.org/draft/2020-12/schema
}

// ExampleBaseLandscape shows the no-overlay sentinel landscape.
func ExampleBaseLandscape() {
	fmt.Println(config.BaseLandscape)
	// Output: base
}

// ExampleAppBlock shows the service-tree identity block.
func ExampleAppBlock() {
	app := config.AppBlock{Landscape: "lapras", Platform: "sulfoxide", Service: "config", Module: "lib", Version: "1.0.0"}
	fmt.Println(app.Landscape, app.Platform, app.Service, app.Module, app.Version)
	// Output: lapras sulfoxide config lib 1.0.0
}

// ExampleAppBlockSchema shows the config-owned app block fragment.
func ExampleAppBlockSchema() {
	fmt.Println(config.AppBlockSchema().Key)
	// Output: app
}

// ExampleBlock shows an engine-owned composable block value.
func ExampleBlock() {
	block := config.Block{Key: "otel", Required: true, Schema: map[string]any{"type": "object"}}
	fmt.Println(block.Key, block.Required, block.Schema["type"])
	// Output: otel true object
}

// ExampleConfig shows a merged configuration tree serving a decoded value.
func ExampleConfig() {
	cfg := config.NewConfig(map[string]any{"demo": map[string]any{"region": "local"}})
	var region string
	_ = cfg.Decode("demo.region", &region)
	fmt.Println(region)
	// Output: local
}

// ExampleIssue shows a readable validation issue.
func ExampleIssue() {
	fmt.Println(config.Issue{Path: "app.version", Message: "required"})
	// Output: app.version: required
}

// ExampleIssue_String shows the "path: message" rendering.
func ExampleIssue_String() {
	fmt.Println(config.Issue{Path: "app.version", Message: "required"}.String())
	// Output: app.version: required
}

// ExampleSchema shows a composed root schema.
func ExampleSchema() {
	schema := config.ComposeSchema(config.AppBlockSchema())
	fmt.Println(schema.Root()["type"])
	// Output: object
}

// ExampleSchema_Root shows reading the composed root as an independent clone.
func ExampleSchema_Root() {
	schema := config.ComposeSchema(config.AppBlockSchema())
	fmt.Println(schema.Root()["additionalProperties"])
	// Output: true
}

// ExampleNewConfig shows wrapping an already-merged tree.
func ExampleNewConfig() {
	cfg := config.NewConfig(map[string]any{"demo": map[string]any{"region": "local"}})
	fmt.Println(cfg.Raw()["demo"])
	// Output: map[region:local]
}

// ExampleNewLoader shows constructing a loader from options.
func ExampleNewLoader() {
	loader := config.NewLoader(config.WithEnvPrefix("ATOMI_"))
	cfg, err := loader.Load(context.Background())
	fmt.Println(cfg, err != nil)
	// Output: <nil> true
}

// ExampleLoader_Load shows loading a validated configuration.
func ExampleLoader_Load() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase))),
		config.WithEnvSource(config.NewMapEnvSource("env", nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Platform)
	// Output: sulfoxide
}

// ExampleOption shows an option value configuring a loader.
func ExampleOption() {
	option := config.WithEnvPrefix("ATOMI_")
	loader := config.NewLoader(option)
	_, err := loader.Load(context.Background())
	fmt.Println(err != nil)
	// Output: true
}

// ExampleWithEnvPrefix shows the required env prefix option.
func ExampleWithEnvPrefix() {
	_, err := config.NewLoader(config.WithEnvPrefix("ATOMI_")).Load(context.Background())
	fmt.Println(err != nil)
	// Output: true
}

// ExampleWithLandscape shows overriding the resolved landscape.
func ExampleWithLandscape() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase))),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", config.NewBytesYAMLSource("overlay", []byte("app:\n  version: 4.0.0\n"))),
		config.WithEnvSource(config.NewMapEnvSource("env", nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Version)
	// Output: 4.0.0
}

// ExampleWithBaseSource shows supplying an in-memory base layer.
func ExampleWithBaseSource() {
	option := config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase)))
	loader := config.NewLoader(config.WithEnvPrefix("ATOMI_"), option, config.WithSchema(config.ComposeSchema(config.AppBlockSchema())))
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Service)
	// Output: config
}

// ExampleWithBaseDir shows file-mode layering rooted at a directory.
func ExampleWithBaseDir() {
	dir, _ := os.MkdirTemp("", "config-basedir")
	defer func() { _ = os.RemoveAll(dir) }()
	_ = os.WriteFile(filepath.Join(dir, "settings.yaml"), []byte(exampleBase), 0o600)
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseDir(dir),
		config.WithEnvSource(config.NewMapEnvSource("env", nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Landscape)
	// Output: base
}

// ExampleWithOverlaySource shows registering an explicit overlay.
func ExampleWithOverlaySource() {
	option := config.WithOverlaySource("lapras", config.NewBytesYAMLSource("overlay", []byte("app:\n  version: 5.0.0\n")))
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase))),
		config.WithLandscape("lapras"),
		option,
		config.WithEnvSource(config.NewMapEnvSource("env", nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Version)
	// Output: 5.0.0
}

// ExampleWithEnvSource shows overriding the env layer with a fake.
func ExampleWithEnvSource() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase))),
		config.WithEnvSource(config.NewMapEnvSource("env", map[string]string{"ATOMI_APP__VERSION": "6.0.0"})),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
	)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Version)
	// Output: 6.0.0
}

// ExampleWithSchema shows supplying the required validation schema.
func ExampleWithSchema() {
	option := config.WithSchema(config.ComposeSchema(config.AppBlockSchema()))
	loader := config.NewLoader(config.WithEnvPrefix("ATOMI_"), config.WithBaseSource(config.NewBytesYAMLSource("base", []byte(exampleBase))), option)
	cfg, _ := loader.Load(context.Background())
	app, _ := cfg.App()
	fmt.Println(app.Module)
	// Output: lib
}

// ExampleWithErrorPortal shows overriding the load-path error portal.
func ExampleWithErrorPortal() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte("app:\n  landscape: base\n"))),
		config.WithEnvSource(config.NewMapEnvSource("env", nil)),
		config.WithSchema(config.ComposeSchema(config.AppBlockSchema())),
		config.WithErrorPortal(problem.LocalErrorPortal()),
	)
	_, err := loader.Load(context.Background())
	issues, _ := config.ValidationIssues(err)
	fmt.Println(len(issues) > 0)
	// Output: true
}

// ExampleYAMLSource shows the YAML layer seam.
func ExampleYAMLSource() {
	var source config.YAMLSource = config.NewBytesYAMLSource("inline", []byte("a: 1"))
	fmt.Println(source.Name())
	// Output: inline
}

// ExampleEnvSource shows the environment layer seam.
func ExampleEnvSource() {
	var source config.EnvSource = config.NewMapEnvSource("fake", nil)
	fmt.Println(source.Name())
	// Output: fake
}

// ExampleBytesYAMLSource shows an in-memory YAML layer.
func ExampleBytesYAMLSource() {
	source := config.NewBytesYAMLSource("inline", []byte("a: 1"))
	fmt.Println(source.Name())
	// Output: inline
}

// ExampleNewBytesYAMLSource shows constructing an in-memory YAML layer.
func ExampleNewBytesYAMLSource() {
	source := config.NewBytesYAMLSource("inline", []byte("a: 1"))
	content, _ := source.Read(context.Background())
	fmt.Println(string(content))
	// Output: a: 1
}

// ExampleBytesYAMLSource_Name shows the layer name.
func ExampleBytesYAMLSource_Name() {
	fmt.Println(config.NewBytesYAMLSource("inline", nil).Name())
	// Output: inline
}

// ExampleBytesYAMLSource_Read shows reading the in-memory document.
func ExampleBytesYAMLSource_Read() {
	content, _ := config.NewBytesYAMLSource("inline", []byte("a: 1")).Read(context.Background())
	fmt.Println(string(content))
	// Output: a: 1
}

// ExampleFileYAMLSource shows a filesystem-backed YAML layer.
func ExampleFileYAMLSource() {
	source := config.NewFileYAMLSource("base", "/etc/config/settings.yaml")
	fmt.Println(source.Path())
	// Output: /etc/config/settings.yaml
}

// ExampleFileYAMLSource_Name shows the layer name.
func ExampleFileYAMLSource_Name() {
	fmt.Println(config.NewFileYAMLSource("base", "/etc/config/settings.yaml").Name())
	// Output: base
}

// ExampleFileYAMLSource_Path shows the configured path.
func ExampleFileYAMLSource_Path() {
	fmt.Println(config.NewFileYAMLSource("base", "/etc/config/settings.yaml").Path())
	// Output: /etc/config/settings.yaml
}

// ExampleFileYAMLSource_Read shows reading a file layer.
func ExampleFileYAMLSource_Read() {
	dir, _ := os.MkdirTemp("", "config-file")
	defer func() { _ = os.RemoveAll(dir) }()
	path := filepath.Join(dir, "settings.yaml")
	_ = os.WriteFile(path, []byte("a: 1"), 0o600)
	content, _ := config.NewFileYAMLSource("base", path).Read(context.Background())
	fmt.Println(string(content))
	// Output: a: 1
}

// ExampleOSEnvSource shows the live process-environment layer.
func ExampleOSEnvSource() {
	fmt.Println(config.NewOSEnvSource().Name())
	// Output: process-environment
}

// ExampleNewOSEnvSource shows constructing the process-environment layer.
func ExampleNewOSEnvSource() {
	fmt.Println(config.NewOSEnvSource().Name())
	// Output: process-environment
}

// ExampleOSEnvSource_Name shows the layer name.
func ExampleOSEnvSource_Name() {
	fmt.Println(config.NewOSEnvSource().Name())
	// Output: process-environment
}

// ExampleOSEnvSource_Environ shows reading the process environment.
func ExampleOSEnvSource_Environ() {
	environment, err := config.NewOSEnvSource().Environ(context.Background())
	fmt.Println(environment != nil, err)
	// Output: true <nil>
}

// ExampleMapEnvSource shows an in-memory env layer.
func ExampleMapEnvSource() {
	source := config.NewMapEnvSource("fake", map[string]string{"K": "V"})
	fmt.Println(source.Name())
	// Output: fake
}

// ExampleNewMapEnvSource shows constructing an in-memory env layer.
func ExampleNewMapEnvSource() {
	environment, _ := config.NewMapEnvSource("fake", map[string]string{"K": "V"}).Environ(context.Background())
	fmt.Println(environment["K"])
	// Output: V
}

// ExampleMapEnvSource_Name shows the layer name.
func ExampleMapEnvSource_Name() {
	fmt.Println(config.NewMapEnvSource("fake", nil).Name())
	// Output: fake
}

// ExampleMapEnvSource_Environ shows reading the in-memory environment.
func ExampleMapEnvSource_Environ() {
	environment, _ := config.NewMapEnvSource("fake", map[string]string{"K": "V"}).Environ(context.Background())
	fmt.Println(environment["K"])
	// Output: V
}

// ExampleYAMLSource_Name shows reading a layer's diagnostic name through the
// interface seam.
func ExampleYAMLSource_Name() {
	var source config.YAMLSource = config.NewBytesYAMLSource("base", []byte("app: {}"))
	fmt.Println(source.Name())
	// Output: base
}

// ExampleYAMLSource_Read shows reading a layer's bytes through the interface seam.
func ExampleYAMLSource_Read() {
	var source config.YAMLSource = config.NewBytesYAMLSource("base", []byte("app: {}"))
	content, _ := source.Read(context.Background())
	fmt.Println(len(content) > 0)
	// Output: true
}

// ExampleEnvSource_Name shows reading the env layer's name through the interface.
func ExampleEnvSource_Name() {
	var source config.EnvSource = config.NewMapEnvSource("env", map[string]string{"A": "1"})
	fmt.Println(source.Name())
	// Output: env
}

// ExampleEnvSource_Environ shows reading the env layer's map through the interface.
func ExampleEnvSource_Environ() {
	var source config.EnvSource = config.NewMapEnvSource("env", map[string]string{"ATOMI_X": "1"})
	environment, _ := source.Environ(context.Background())
	fmt.Println(environment["ATOMI_X"])
	// Output: 1
}

// ExampleAppBlock_landscape shows the service-tree landscape field.
func ExampleAppBlock_landscape() {
	fmt.Println(config.AppBlock{Landscape: "lapras"}.Landscape)
	// Output: lapras
}

// ExampleAppBlock_platform shows the service-tree platform field.
func ExampleAppBlock_platform() {
	fmt.Println(config.AppBlock{Platform: "sulfoxide"}.Platform)
	// Output: sulfoxide
}

// ExampleAppBlock_service shows the service-tree service field.
func ExampleAppBlock_service() {
	fmt.Println(config.AppBlock{Service: "config"}.Service)
	// Output: config
}

// ExampleAppBlock_module shows the service-tree module field.
func ExampleAppBlock_module() {
	fmt.Println(config.AppBlock{Module: "lib"}.Module)
	// Output: lib
}

// ExampleAppBlock_version shows the service-tree version field.
func ExampleAppBlock_version() {
	fmt.Println(config.AppBlock{Version: "1.0.0"}.Version)
	// Output: 1.0.0
}

// ExampleBlock_key shows the root property a block mounts under.
func ExampleBlock_key() {
	fmt.Println(config.NewBlock("otel", true, map[string]any{"type": "object"}).Key)
	// Output: otel
}

// ExampleBlock_required shows whether a block is mandatory in the composed root.
func ExampleBlock_required() {
	fmt.Println(config.NewBlock("otel", true, map[string]any{"type": "object"}).Required)
	// Output: true
}

// ExampleBlock_schema shows the fragment a block carries.
func ExampleBlock_schema() {
	fmt.Println(config.NewBlock("otel", true, map[string]any{"type": "object"}).Schema["type"])
	// Output: object
}

// ExampleIssue_path shows the dotted location of a validation issue.
func ExampleIssue_path() {
	fmt.Println(config.Issue{Path: "app.landscape", Message: "required"}.Path)
	// Output: app.landscape
}

// ExampleIssue_message shows the reason a value was rejected.
func ExampleIssue_message() {
	fmt.Println(config.Issue{Path: "app.landscape", Message: "required"}.Message)
	// Output: required
}
