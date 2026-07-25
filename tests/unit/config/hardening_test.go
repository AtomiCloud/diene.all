package config_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	problemtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
)

// nilYAML is a typed-nil-able YAMLSource used to prove typed-nil rejection.
type nilYAML struct{}

func (*nilYAML) Name() string                         { return "nil-yaml" }
func (*nilYAML) Read(context.Context) ([]byte, error) { return nil, nil }

func loadHardening(t *testing.T, options ...config.Option) (*config.Config, error) {
	t.Helper()
	base := make([]config.Option, 0, 4+len(options))
	base = append(
		base,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	return config.NewLoader(append(base, options...)...).Load(context.Background())
}

func TestNewLoaderIgnoresNilOption(t *testing.T) {
	t.Parallel()
	cfg, err := config.NewLoader(
		nil,
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	testhelper.RequireConfig(t, cfg, err)
}

func TestLoadRejectsNilEnvSource(t *testing.T) {
	t.Parallel()
	_, err := loadHardening(t, config.WithEnvSource(nil))
	if err == nil {
		t.Fatal("a nil env source must fail fast")
	}
}

func TestLoadRejectsTypedNilBaseSource(t *testing.T) {
	t.Parallel()
	var typedNil *nilYAML
	_, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(typedNil),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	if err == nil {
		t.Fatal("a typed-nil base source must fail fast without panicking")
	}
}

func TestLoadRejectsNilOverlaySource(t *testing.T) {
	t.Parallel()
	cfg, err := loadHardening(
		t,
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", nil),
	)
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	testhelper.RequireIssue(t, loadErr, "app.landscape")
}

func TestLoadRejectsBaseKeyCollision(t *testing.T) {
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
  data-dir: a
  dataDir: b
`
	cfg, err := loadHardening(t, config.WithBaseSource(testhelper.BaseSource(base)))
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	if _, ok := config.ValidationIssues(loadErr); !ok {
		t.Fatalf("a base key collision must be a validation problem: %v", loadErr)
	}
}

func TestLoadRejectsOverlayKeyCollision(t *testing.T) {
	t.Parallel()
	overlay := testhelper.SchemaPointer + `
app:
  landscape: lapras
demo:
  cache-region: a
  cacheRegion: b
`
	cfg, err := loadHardening(
		t,
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", overlay)),
	)
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	if _, ok := config.ValidationIssues(loadErr); !ok {
		t.Fatalf("an overlay key collision must be a validation problem: %v", loadErr)
	}
}

func TestLoadRejectsEnvKeyCollision(t *testing.T) {
	t.Parallel()
	cfg, err := loadHardening(t, config.WithEnvSource(testhelper.EnvSource(map[string]string{
		"ATOMI_CACHE_REGION": "a",
		"ATOMI_CACHEREGION":  "b",
	})))
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	if _, ok := config.ValidationIssues(loadErr); !ok {
		t.Fatalf("an env key collision must be a validation problem: %v", loadErr)
	}
}

func TestValidateRejectsTypedContainerAlias(t *testing.T) {
	t.Parallel()
	// A legal nested map[string]string carries case-only aliases; Validate must
	// reject them deterministically after normalization, not miss them.
	schema := config.ComposeSchema(config.AppBlockSchema())
	instance := map[string]any{
		"app": map[string]any{
			"landscape": "lapras", "platform": "sulfoxide",
			"service": "config", "module": "lib", "version": "1.0.0",
		},
		"svc": map[string]string{"cache-region": "a", "cacheRegion": "b"},
	}
	if _, ok := config.ValidationIssues(schema.Validate(instance)); !ok {
		t.Fatal("a typed-container alias must be a validation problem")
	}
}

func TestDecodeRejectsAmbiguousKey(t *testing.T) {
	t.Parallel()
	// NewConfig is a bypass; Decode must be deterministic on colliding siblings
	// rather than pick one by map iteration order.
	cfg := config.NewConfig(map[string]any{"demo": map[string]any{"data-dir": 1, "dataDir": 2}})
	// Neither the canonical spelling nor an exact sibling spelling resolves while
	// a canonical alias sibling is present.
	if err := cfg.Decode("demo.datadir", new(int)); err == nil {
		t.Fatal("an ambiguous canonical key must not resolve")
	}
	if err := cfg.Decode("demo.dataDir", new(int)); err == nil {
		t.Fatal("an exact-hit key must not resolve when an alias sibling exists")
	}
}

func TestLoadProblemUsesSchemaPortalAndOverride(t *testing.T) {
	t.Parallel()
	// A non-validation load-path failure (env collision) mints its type URI from
	// the schema's portal by default.
	schema := testhelper.Schema().WithPortal(problemtest.SampleErrorPortal())
	collidingEnv := config.WithEnvSource(testhelper.EnvSource(map[string]string{
		"ATOMI_CACHE_REGION": "a",
		"ATOMI_CACHEREGION":  "b",
	}))

	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithSchema(schema),
		collidingEnv,
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	var problemErr *problem.Error
	if !errors.As(loadErr, &problemErr) || !strings.Contains(problemErr.Problem.Type, "raichu") {
		t.Fatalf("schema portal must be the default load-path portal: %v", loadErr)
	}

	// WithErrorPortal overrides the schema portal.
	cfg, err = config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithSchema(schema),
		config.WithErrorPortal(problem.LocalErrorPortal()),
		collidingEnv,
	).Load(context.Background())
	loadErr = testhelper.RequireLoadError(t, cfg, err)
	if !errors.As(loadErr, &problemErr) || !strings.Contains(problemErr.Problem.Type, "local.atomi.cloud") {
		t.Fatalf("WithErrorPortal must override the schema portal: %v", loadErr)
	}
}
