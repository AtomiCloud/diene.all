package config_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
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

// TestLoadThreeLayerPrecedence is the branch-safe behavioral gate mirroring the
// tag-only proxy consumer: it proves base defaults, a sparse overlay, and an
// indexed env override compose in order, asserting a base-only field, an
// overlay-won field, and an env-won field on one load.
func TestLoadThreeLayerPrecedence(t *testing.T) {
	t.Parallel()
	cfg, loadErr := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.OverlayDocument("lapras"))),
		config.WithEnvSource(testhelper.EnvSource(map[string]string{"ATOMI_APP__VERSION": "9.9.9"})),
		config.WithSchema(testhelper.Schema()),
	)
	got := testhelper.RequireConfig(t, cfg, loadErr)

	app, err := got.App()
	if err != nil {
		t.Fatalf("app: %v", err)
	}
	if app.Platform != "sulfoxide" {
		t.Fatalf("base-only field lost: platform = %q", app.Platform)
	}
	if app.Version != "9.9.9" {
		t.Fatalf("env layer must win: version = %q", app.Version)
	}
	var region string
	if err := got.Decode("demo.region", &region); err != nil {
		t.Fatalf("decode region: %v", err)
	}
	if region != "ap-southeast-1" {
		t.Fatalf("overlay layer must win over base: region = %q", region)
	}
}

// TestLoadCrossSpellingBaseToOverlayMatrix proves R14 canonical base-to-overlay
// merging with NO env layer masking the result: a value spelled camel in the
// base and kebab in the overlay collapses to a single entry that the overlay
// wins, so an overlay can override a base value written in a different casing
// and Decode is deterministic.
func TestLoadCrossSpellingBaseToOverlayMatrix(t *testing.T) {
	t.Parallel()
	spellings := []struct {
		name         string
		baseKey      string
		overlayKey   string
		decodeKey    string
		canonicalKey string
	}{
		{"camel-base-kebab-overlay", "dataDir", "data-dir", "demo.dataDir", "datadir"},
		{"snake-base-pascal-overlay", "cache_root", "CacheRoot", "demo.cacheRoot", "cacheroot"},
		{"kebab-base-camel-overlay", "log-level", "logLevel", "demo.logLevel", "loglevel"},
	}
	for _, spelling := range spellings {
		t.Run(spelling.name, func(t *testing.T) {
			t.Parallel()
			base := testhelper.SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
demo:
  region: local
  ` + spelling.baseKey + `: base-value
`
			overlay := testhelper.SchemaPointer + `
app:
  landscape: lapras
demo:
  ` + spelling.overlayKey + `: overlay-value
`
			// No env layer: the assertion isolates base-to-overlay precedence.
			cfg, loadErr := loadWith(
				t,
				config.WithEnvPrefix("ATOMI_"),
				config.WithBaseSource(testhelper.BaseSource(base)),
				config.WithLandscape("lapras"),
				config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", overlay)),
				config.WithEnvSource(testhelper.EnvSource(nil)),
				config.WithSchema(testhelper.Schema()),
			)
			got := testhelper.RequireConfig(t, cfg, loadErr)

			var value string
			if err := got.Decode(spelling.decodeKey, &value); err != nil {
				t.Fatalf("decode: %v", err)
			}
			if value != "overlay-value" {
				t.Fatalf("overlay spelling must win over base across casings: %q", value)
			}
			demo, ok := got.Raw()["demo"].(map[string]any)
			if !ok {
				t.Fatalf("demo block missing: %v", got.Raw())
			}
			matches := 0
			for key := range demo {
				if coreutils.CanonicalConfigKey(key) == spelling.canonicalKey {
					matches++
				}
			}
			if matches != 1 {
				t.Fatalf("cross-spelling variants must collapse to one key, found %d in %v", matches, demo)
			}
		})
	}
}

// TestLoadAlignsCrossSpelledKeysToStrictSchema is the R14 proof that a value
// spelled camel, kebab, or snake in YAML validates against a strict snake_case
// schema property and decodes. Viper lowercases camelCase to cacheregion while
// JSON Schema property matching is exact, so without instance-to-schema key
// alignment a strict additionalProperties:false schema would reject the value
// the contract says matches across casings.
func TestLoadAlignsCrossSpelledKeysToStrictSchema(t *testing.T) {
	t.Parallel()
	strict := config.NewBlock("svc", true, map[string]any{
		"type": "object",
		"properties": map[string]any{
			"cache_region": map[string]any{"type": "string", "minLength": float64(1)},
		},
		"required":             []any{"cache_region"},
		"additionalProperties": false,
	})
	schema := config.ComposeSchema(config.AppBlockSchema(), strict)

	for _, spelling := range []string{"cacheRegion", "cache-region", "cache_region"} {
		t.Run(spelling, func(t *testing.T) {
			t.Parallel()
			base := testhelper.SchemaPointer + `
app:
  landscape: base
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
svc:
  ` + spelling + `: ap-southeast-1
`
			cfg, loadErr := loadWith(
				t,
				config.WithEnvPrefix("ATOMI_"),
				config.WithBaseSource(testhelper.BaseSource(base)),
				config.WithEnvSource(testhelper.EnvSource(nil)),
				config.WithSchema(schema),
			)
			got := testhelper.RequireConfig(t, cfg, loadErr)
			var region string
			if err := got.Decode("svc.cacheRegion", &region); err != nil {
				t.Fatalf("decode: %v", err)
			}
			if region != "ap-southeast-1" {
				t.Fatalf("cross-spelled value must validate and decode: %q", region)
			}
		})
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

func TestLoadRequiresEnvPrefix(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithSchema(testhelper.Schema()),
	)
	if err == nil {
		t.Fatal("a loader with no env prefix must fail fast")
	}
}

func TestLoadRequiresBaseSource(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithSchema(testhelper.Schema()),
	)
	if err == nil {
		t.Fatal("a loader with no base source must fail fast")
	}
}

func TestLoadRequiresSchema(t *testing.T) {
	t.Parallel()
	// A generic library cannot infer a service-composed root schema, so Load must
	// reject a missing schema rather than silently skipping startup validation.
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
	)
	if err == nil {
		t.Fatal("a loader with no schema must fail fast")
	}
}

func TestLoadReportsBaseReadError(t *testing.T) {
	t.Parallel()
	_, err := loadWith(
		t,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(failingYAML{name: "base"}),
		config.WithSchema(testhelper.Schema()),
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
		config.WithSchema(testhelper.Schema()),
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
		config.WithSchema(testhelper.Schema()),
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
		config.WithSchema(testhelper.Schema()),
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
		config.WithSchema(testhelper.Schema()),
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
		config.WithSchema(testhelper.Schema()),
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
	// A valid landscape with no overlay source and no base dir simply uses the
	// base.
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
