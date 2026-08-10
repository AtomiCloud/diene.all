package testhelper_test

import (
	"context"
	"fmt"
	"strings"

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

// ExampleTestingT shows the minimal testing interface the assertions depend on;
// any type with Helper and Fatalf (including *testing.T) satisfies it.
func ExampleTestingT() {
	var recorder testhelper.TestingT = noopT{}
	recorder.Helper()
	fmt.Println("satisfied")
	// Output: satisfied
}

// ExampleTestingT_Helper shows marking the calling function as a test helper
// through the minimal testing interface.
func ExampleTestingT_Helper() {
	var recorder testhelper.TestingT = noopT{}
	recorder.Helper()
	fmt.Println("marked as helper")
	// Output: marked as helper
}

// ExampleTestingT_Fatalf shows reporting a fatal assertion through the interface.
func ExampleTestingT_Fatalf() {
	var recorder testhelper.TestingT = noopT{}
	recorder.Fatalf("value %d was invalid", 42)
	fmt.Println("reported")
	// Output: reported
}

// ExampleDemoBlockKey shows the neutral demo block's root key.
func ExampleDemoBlockKey() {
	fmt.Println(testhelper.DemoBlockKey)
	// Output: demo
}

// ExampleSchemaPointer shows the first-line schema pointer fixtures declare.
func ExampleSchemaPointer() {
	fmt.Println(testhelper.SchemaPointer)
	// Output: # yaml-language-server: $schema=./config.schema.json
}

// ExampleSchema shows the composed app-plus-demo fixture schema.
func ExampleSchema() {
	fmt.Println(testhelper.Schema().Root()["type"])
	// Output: object
}

// ExampleDemoBlock shows the neutral demo block fixture.
func ExampleDemoBlock() {
	fmt.Println(testhelper.DemoBlock().Key, testhelper.DemoBlock().Required)
	// Output: demo true
}

// ExampleOverlaySource shows an in-memory overlay layer fixture.
func ExampleOverlaySource() {
	source := testhelper.OverlaySource("lapras", testhelper.OverlayDocument("lapras"))
	fmt.Println(source.Name())
	// Output: testhelper:overlay:lapras
}

// ExampleEnvSource shows an in-memory env layer fixture.
func ExampleEnvSource() {
	source := testhelper.EnvSource(map[string]string{"K": "V"})
	fmt.Println(source.Name())
	// Output: testhelper:env
}

// ExampleBaseDocument shows the base document declares the schema on line one.
func ExampleBaseDocument() {
	firstLine, _, _ := strings.Cut(testhelper.BaseDocument(), "\n")
	fmt.Println(firstLine == testhelper.SchemaPointer)
	// Output: true
}

// ExampleOverlayDocument shows the sparse overlay fixture for a landscape.
func ExampleOverlayDocument() {
	firstLine, _, _ := strings.Cut(testhelper.OverlayDocument("lapras"), "\n")
	fmt.Println(firstLine == testhelper.SchemaPointer)
	// Output: true
}

// ExampleInvalidOverlayDocument shows the fail-fast overlay fixture.
func ExampleInvalidOverlayDocument() {
	firstLine, _, _ := strings.Cut(testhelper.InvalidOverlayDocument(), "\n")
	fmt.Println(firstLine == testhelper.SchemaPointer)
	// Output: true
}

// ExampleValidRaw shows the schema-valid stub map fixture.
func ExampleValidRaw() {
	cfg := config.NewConfig(testhelper.ValidRaw())
	app, _ := cfg.App()
	fmt.Println(app.Landscape)
	// Output: lapras
}
