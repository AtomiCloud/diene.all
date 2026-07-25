package config_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

// failingYAML is a YAMLSource that always errors, exercising the loader's layer
// read-error paths.
type failingYAML struct{ name string }

func (s failingYAML) Name() string { return s.name }
func (failingYAML) Read(context.Context) ([]byte, error) {
	return nil, errors.New("boom")
}

// failingEnv is an EnvSource that always errors.
type failingEnv struct{}

func (failingEnv) Name() string { return "failing-env" }
func (failingEnv) Environ(context.Context) (map[string]string, error) {
	return nil, errors.New("no environment")
}

func loadWith(t *testing.T, options ...config.Option) (*config.Config, error) {
	t.Helper()
	return config.NewLoader(options...).Load(context.Background())
}

func TestLoadMergesBaseOverlayEnvInPrecedence(t *testing.T) {
	t.Parallel()
	cfg, loadErr := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.OverlayDocument("lapras"))),
		config.WithEnvSource(testhelper.EnvSource(map[string]string{
			"ATOMI_DEMO__REGION": "envregion",
		})),
		config.WithSchema(testhelper.Schema()),
	)
	got := testhelper.RequireConfig(t, cfg, loadErr)

	var region string
	if err := got.Decode("demo.region", &region); err != nil {
		t.Fatalf("decode region: %v", err)
	}
	if region != "envregion" {
		t.Fatalf("env must win: region = %q", region)
	}
	app, err := got.App()
	if err != nil {
		t.Fatalf("app: %v", err)
	}
	if app.Landscape != "lapras" || app.Platform != "sulfoxide" {
		t.Fatalf("overlay+base app merge wrong: %+v", app)
	}
}

func TestLoadBaseOnlyWhenLandscapeIsSentinel(t *testing.T) {
	t.Parallel()
	// Base app.landscape is "base": no overlay is applied even when one is
	// registered.
	cfg, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithOverlaySource("base", testhelper.OverlaySource("base", testhelper.OverlayDocument("base"))),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	got := testhelper.RequireConfig(t, cfg, err)
	var region string
	if err := got.Decode("demo.region", &region); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if region != "local" {
		t.Fatalf("base value must survive: %q", region)
	}
}

func TestLoadIndexedEnvListReplacesYAMLList(t *testing.T) {
	t.Parallel()
	cfg, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(map[string]string{
			"ATOMI_DEMO__REPLICAS__0": "10",
			"ATOMI_DEMO__REPLICAS__1": "20",
			"ATOMI_DEMO__REPLICAS__2": "30",
		})),
		config.WithSchema(testhelper.Schema()),
	)
	got := testhelper.RequireConfig(t, cfg, err)
	var replicas []int
	if err := got.Decode("demo.replicas", &replicas); err != nil {
		t.Fatalf("decode replicas: %v", err)
	}
	if len(replicas) != 3 || replicas[0] != 10 || replicas[2] != 30 {
		t.Fatalf("indexed env list wrong: %v", replicas)
	}
}

func TestLoadInvalidOverlayFailsFastWithProblem(t *testing.T) {
	t.Parallel()
	cfg, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.InvalidOverlayDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	issue := testhelper.RequireIssue(t, loadErr, "app.version")
	if issue.Message == "" {
		t.Fatal("expected a readable issue message")
	}
}

func TestLoadValidatesOnlyFinalMergedLayer(t *testing.T) {
	t.Parallel()
	// Base blanks the version (invalid alone); env fills it. The merged tree is
	// valid, so validation, which runs only on the final layer, must pass.
	base := testhelper.SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: ""
demo:
  region: local
`
	cfg, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(base)),
		config.WithEnvSource(testhelper.EnvSource(map[string]string{
			"ATOMI_APP__VERSION": "9.9.9",
		})),
		config.WithSchema(testhelper.Schema()),
	)
	got := testhelper.RequireConfig(t, cfg, err)
	app, err := got.App()
	if err != nil {
		t.Fatalf("app: %v", err)
	}
	if app.Version != "9.9.9" {
		t.Fatalf("env should complete the merged tree: %+v", app)
	}
}

func TestLoadWithoutSchemaSkipsValidation(t *testing.T) {
	t.Parallel()
	// No schema configured: even an incomplete document loads (merge only).
	cfg, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.SchemaPointer+"\nonly: value\n")),
		config.WithEnvSource(testhelper.EnvSource(nil)),
	)
	got := testhelper.RequireConfig(t, cfg, err)
	if _, ok := got.Raw()["only"]; !ok {
		t.Fatalf("merge-only load lost data: %v", got.Raw())
	}
}

func TestLoadRequiresEnvPrefix(t *testing.T) {
	t.Parallel()
	_, err := loadWith(t, config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())))
	if err == nil {
		t.Fatal("a loader with no env prefix must fail fast")
	}
}

func TestLoadRequiresBaseSource(t *testing.T) {
	t.Parallel()
	_, err := loadWith(t, config.WithEnvPrefix("ATOMI_"))
	if err == nil {
		t.Fatal("a loader with no base source must fail fast")
	}
}

func TestLoadReportsBaseReadError(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(failingYAML{name: "base"}),
	)
	if err == nil {
		t.Fatal("base read error must surface")
	}
}

func TestLoadReportsOverlayReadError(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", failingYAML{name: "overlay"}),
	)
	if err == nil {
		t.Fatal("overlay read error must surface")
	}
}

func TestLoadReportsEnvReadError(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(failingEnv{}),
	)
	if err == nil {
		t.Fatal("env read error must surface")
	}
}

func TestLoadReportsMalformedBaseYAML(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource("\t not: [valid")),
	)
	if _, ok := config.ValidationIssues(err); !ok {
		t.Fatalf("malformed base YAML must be a validation problem, got %v", err)
	}
}

func TestLoadReportsMalformedOverlayYAML(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", "\t not: [valid")),
	)
	if _, ok := config.ValidationIssues(err); !ok {
		t.Fatalf("malformed overlay YAML must be a validation problem, got %v", err)
	}
}

func TestLoadReportsEnvCoercionError(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(map[string]string{
			// Sparse indexes (0 then 2) are rejected by core-utils.
			"ATOMI_DEMO__REPLICAS__0": "1",
			"ATOMI_DEMO__REPLICAS__2": "3",
		})),
	)
	issues, ok := config.ValidationIssues(err)
	if !ok || len(issues) == 0 {
		t.Fatalf("env coercion failure must be a validation problem, got %v", err)
	}
}

func TestLoadResolvesLandscapeFromBaseAppBlock(t *testing.T) {
	t.Parallel()
	base := testhelper.SchemaPointer + `
app:
  landscape: pichu
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
demo:
  region: local
`
	cfg, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(base)),
		config.WithOverlaySource("pichu", testhelper.OverlaySource("pichu", testhelper.SchemaPointer+"\ndemo:\n  region: pichu-region\n")),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	got := testhelper.RequireConfig(t, cfg, err)
	var region string
	if err := got.Decode("demo.region", &region); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if region != "pichu-region" {
		t.Fatalf("overlay resolved from app.landscape should apply: %q", region)
	}
}

func TestLoadLandscapeWithoutRegisteredOverlayIsBaseOnly(t *testing.T) {
	t.Parallel()
	// A landscape with no overlay source and no base dir simply uses the base.
	cfg, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("unregistered"),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	got := testhelper.RequireConfig(t, cfg, err)
	var region string
	if err := got.Decode("demo.region", &region); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if region != "local" {
		t.Fatalf("expected base value: %q", region)
	}
}
