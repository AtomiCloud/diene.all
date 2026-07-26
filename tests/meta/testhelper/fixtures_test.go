package testhelper_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

func TestSchemaComposesValidatableRoot(t *testing.T) {
	t.Parallel()
	schema := testhelper.Schema()
	if _, present := schema.Root()["properties"].(map[string]any)[testhelper.DemoBlockKey]; !present {
		t.Fatal("the demo block must be composed into the schema")
	}
	// The demo block is a stub, never a real engine block.
	if testhelper.DemoBlock().Key != testhelper.DemoBlockKey {
		t.Fatalf("demo block key mismatch: %q", testhelper.DemoBlock().Key)
	}
}

func TestBaseDocumentDeclaresSchemaOnFirstLine(t *testing.T) {
	t.Parallel()
	documents := map[string]string{
		"base":            testhelper.BaseDocument(),
		"overlay":         testhelper.OverlayDocument("lapras"),
		"invalid-overlay": testhelper.InvalidOverlayDocument(),
	}
	for name, document := range documents {
		firstLine, _, _ := strings.Cut(document, "\n")
		if firstLine != testhelper.SchemaPointer {
			t.Fatalf("%s document first line must be the schema pointer, got %q", name, firstLine)
		}
	}
}

func TestFixturesDriveTheRealLoader(t *testing.T) {
	t.Parallel()
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.OverlayDocument("lapras"))),
		config.WithEnvSource(testhelper.EnvSource(map[string]string{"ATOMI_DEMO__SECRET": "from-env"})),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	got := testhelper.RequireConfig(t, cfg, err)
	var secret string
	if err := got.Decode("demo.secret", &secret); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if secret != "from-env" {
		t.Fatalf("env fake did not drive the loader: %q", secret)
	}
}

func TestInvalidSchemaBlockCannotCompile(t *testing.T) {
	t.Parallel()
	schema := config.ComposeSchema(testhelper.InvalidSchemaBlock())
	if err := schema.Validate(testhelper.ValidRaw()); err == nil {
		t.Fatal("the invalid-schema fixture must fail to compile")
	}
}

func TestValidRawSatisfiesSchema(t *testing.T) {
	t.Parallel()
	// ValidRaw is the map documented as schema-valid, so the claim is proven.
	if err := testhelper.Schema().Validate(testhelper.ValidRaw()); err != nil {
		t.Fatalf("ValidRaw must satisfy the schema: %v", err)
	}
}

func TestStubBuildersAreUncheckedWrappers(t *testing.T) {
	t.Parallel()
	// StubConfig is documented as an unchecked wrapper: it must accept a map that
	// would fail schema validation, decoding it verbatim.
	stub := testhelper.StubConfig(map[string]any{"demo": map[string]any{"region": "here"}})
	if testhelper.Schema().Validate(stub.Raw()) == nil {
		t.Fatal("the probe map should not satisfy the schema (proving StubConfig is unchecked)")
	}
	var region string
	if err := stub.Decode("demo.region", &region); err != nil || region != "here" {
		t.Fatalf("unchecked stub must still decode: %q %v", region, err)
	}
	// StubApp is likewise unchecked but decodes its app block.
	app, err := testhelper.StubApp(config.AppBlock{
		Landscape: "lapras", Platform: "sulfoxide",
		Service: "config", Module: "lib", Version: "1.0.0",
	}).App()
	if err != nil || app.Service != "config" {
		t.Fatalf("StubApp wrong: %+v %v", app, err)
	}
}

// TestFakeAndRealSourcesAgree is the real-vs-fake contract-parity check: the
// in-memory fake source and a real file source with identical content decode to
// the same value through the loader.
func TestFakeAndRealSourcesAgree(t *testing.T) {
	t.Parallel()
	document := testhelper.BaseDocument()

	fakeCfg, fakeErr := load(t, testhelper.BaseSource(document))
	fake := testhelper.RequireConfig(t, fakeCfg, fakeErr)

	dir := t.TempDir()
	path := filepath.Join(dir, "settings.yaml")
	if err := os.WriteFile(path, []byte(document), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	realCfg, realErr := load(t, config.NewFileYAMLSource("base", path))
	realConfig := testhelper.RequireConfig(t, realCfg, realErr)

	var fakeRegion, realRegion string
	if err := fake.Decode("demo.region", &fakeRegion); err != nil {
		t.Fatalf("fake decode: %v", err)
	}
	if err := realConfig.Decode("demo.region", &realRegion); err != nil {
		t.Fatalf("real decode: %v", err)
	}
	if fakeRegion != realRegion {
		t.Fatalf("fake %q and realConfig %q sources disagree", fakeRegion, realRegion)
	}
}

func load(t *testing.T, base config.YAMLSource) (*config.Config, error) {
	t.Helper()
	return config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(base),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
}
