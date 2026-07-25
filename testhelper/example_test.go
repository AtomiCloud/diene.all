package testhelper_test

import (
	"context"
	"fmt"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

// noopT is a stand-in TestingT for the runnable examples.
type noopT struct{}

func (noopT) Helper()               {}
func (noopT) Fatalf(string, ...any) {}

// ExampleRequireConfig shows the happy-path assertion: drive the real loader
// over in-memory fakes and assert a successful load in one call.
func ExampleRequireConfig() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	cfg, err := loader.Load(context.Background())
	cfg = testhelper.RequireConfig(noopT{}, cfg, err)
	app, _ := cfg.App()
	fmt.Println(app.Service)
	// Output: config
}

// ExampleBaseSource shows the in-memory base, overlay, and env fakes driving the
// real loader through all three layers without touching the filesystem.
func ExampleBaseSource() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.OverlayDocument("lapras"))),
		config.WithEnvSource(testhelper.EnvSource(map[string]string{"ATOMI_DEMO__SECRET": "from-env"})),
		config.WithSchema(testhelper.Schema()),
	)
	cfg, err := loader.Load(context.Background())
	got := testhelper.RequireConfig(noopT{}, cfg, err)
	var secret string
	_ = got.Decode("demo.secret", &secret)
	fmt.Println(secret)
	// Output: from-env
}

// ExampleRequireLoadError shows the fail-fast assertion recovering the error
// from an invalid overlay whose merged result violates the schema.
func ExampleRequireLoadError() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.InvalidOverlayDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	cfg, err := loader.Load(context.Background())
	loadErr := testhelper.RequireLoadError(noopT{}, cfg, err)
	fmt.Println(loadErr != nil)
	// Output: true
}

// ExampleRequireIssue shows recovering a specific validation issue by path.
func ExampleRequireIssue() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.InvalidOverlayDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	_, err := loader.Load(context.Background())
	issue := testhelper.RequireIssue(noopT{}, err, "app.version")
	fmt.Println(issue.Path)
	// Output: app.version
}

// ExampleStubConfig shows minting a pre-merged config stub without the loader.
func ExampleStubConfig() {
	cfg := testhelper.StubConfig(testhelper.ValidRaw())
	app, _ := cfg.App()
	fmt.Println(app.Landscape)
	// Output: lapras
}

// ExampleStubApp shows a stub carrying only the service-tree block.
func ExampleStubApp() {
	cfg := testhelper.StubApp(config.AppBlock{Landscape: "pichu", Service: "config"})
	app, _ := cfg.App()
	fmt.Println(app.Landscape, app.Service)
	// Output: pichu config
}

// ExampleInvalidSchemaBlock shows the uncompilable-schema fixture surfacing a
// fault rather than a validation problem.
func ExampleInvalidSchemaBlock() {
	err := config.ComposeSchema(testhelper.InvalidSchemaBlock()).Validate(testhelper.ValidRaw())
	_, isValidationProblem := config.ValidationIssues(err)
	fmt.Println(err != nil, isValidationProblem)
	// Output: true false
}
