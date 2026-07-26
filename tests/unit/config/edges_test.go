package config_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	problemtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
)

func TestLoadFileModeWithAbsentOverlay(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "settings.yaml"), []byte(testhelper.BaseDocument()), 0o600); err != nil {
		t.Fatalf("write base: %v", err)
	}
	// Landscape "lapras" resolves settings.lapras.yaml, which is absent, so the
	// overlay is a no-op and the base defaults stand.
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseDir(dir),
		config.WithLandscape("lapras"),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	got := testhelper.RequireConfig(t, cfg, err)
	var region string
	if err := got.Decode("demo.region", &region); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if region != "local" {
		t.Fatalf("absent overlay must leave base intact: %q", region)
	}
}

func TestLoadFileModeWithPresentOverlay(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "settings.yaml"), []byte(testhelper.BaseDocument()), 0o600); err != nil {
		t.Fatalf("write base: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "settings.lapras.yaml"), []byte(testhelper.OverlayDocument("lapras")), 0o600); err != nil {
		t.Fatalf("write overlay: %v", err)
	}
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseDir(dir),
		config.WithLandscape("lapras"),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	got := testhelper.RequireConfig(t, cfg, err)
	var region string
	if err := got.Decode("demo.region", &region); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if region != "ap-southeast-1" {
		t.Fatalf("file-mode overlay must apply: %q", region)
	}
}

func TestLoadUsesConfiguredErrorPortal(t *testing.T) {
	t.Parallel()
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("lapras"),
		config.WithOverlaySource("lapras", testhelper.OverlaySource("lapras", testhelper.InvalidOverlayDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
		config.WithErrorPortal(problemtest.SampleErrorPortal()),
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	var problemErr *problem.Error
	if !errors.As(loadErr, &problemErr) {
		t.Fatalf("expected a problem error, got %v", loadErr)
	}
	if problemErr.Problem.Type != "https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/validation-error" {
		t.Fatalf("configured portal identity missing from type URI: %q", problemErr.Problem.Type)
	}
}

func TestValidateReportsUnmarshalableFragment(t *testing.T) {
	t.Parallel()
	schema := config.ComposeSchema(config.NewBlock("bad", true, map[string]any{"x": make(chan int)}))
	if err := schema.Validate(validInstance()); err == nil {
		t.Fatal("an unmarshalable schema fragment must error")
	}
}

func TestValidateReportsRootLevelIssue(t *testing.T) {
	t.Parallel()
	// An empty instance is missing the required app and demo blocks; that failure
	// is anchored at the document root.
	err := testhelper.Schema().Validate(map[string]any{})
	issues, ok := config.ValidationIssues(err)
	if !ok {
		t.Fatalf("expected a validation problem, got %v", err)
	}
	foundRoot := false
	for _, issue := range issues {
		if issue.Path == "(root)" {
			foundRoot = true
		}
	}
	if !foundRoot {
		t.Fatalf("expected a root-anchored issue, got %v", issues)
	}
}

func TestLoadRejectsExplicitTraversalLandscape(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "settings.yaml"), []byte(testhelper.BaseDocument()), 0o600); err != nil {
		t.Fatalf("write base: %v", err)
	}
	// A planted file where a traversal would resolve must never be read.
	if err := os.WriteFile(filepath.Join(dir, "settings.escape.yaml"), []byte(testhelper.OverlayDocument("escape")), 0o600); err != nil {
		t.Fatalf("write planted: %v", err)
	}
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseDir(dir),
		config.WithLandscape("../../../../etc/passwd"),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	testhelper.RequireIssue(t, loadErr, "app.landscape")
}

func TestLoadRejectsBaseDerivedTraversalLandscape(t *testing.T) {
	t.Parallel()
	base := testhelper.SchemaPointer + `
app:
  landscape: "../../secret"
  platform: sulfoxide
  service: config
  module: lib
  version: 1.0.0
demo:
  region: local
`
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "settings.yaml"), []byte(base), 0o600); err != nil {
		t.Fatalf("write base: %v", err)
	}
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseDir(dir),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	testhelper.RequireIssue(t, loadErr, "app.landscape")
}

func TestLoadRejectsMaliciousRegisteredLandscape(t *testing.T) {
	t.Parallel()
	// A malicious landscape registered as an explicit overlay is still rejected by
	// the token grammar before the overlay is read.
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("../evil"),
		config.WithOverlaySource("../evil", testhelper.OverlaySource("evil", testhelper.OverlayDocument("evil"))),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	testhelper.RequireIssue(t, loadErr, "app.landscape")
}

func TestLoadRejectsMaliciousLandscapeWithoutOverlay(t *testing.T) {
	t.Parallel()
	// A malicious landscape with no overlay source and no base dir is still
	// rejected rather than silently ignored.
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithLandscape("../evil"),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	).Load(context.Background())
	loadErr := testhelper.RequireLoadError(t, cfg, err)
	testhelper.RequireIssue(t, loadErr, "app.landscape")
}

func TestNewConfigClonesCallerMap(t *testing.T) {
	t.Parallel()
	raw := map[string]any{"app": map[string]any{"service": "config"}}
	cfg := config.NewConfig(raw)
	raw["app"].(map[string]any)["service"] = "mutated"
	var service string
	if err := cfg.Decode("app.service", &service); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if service != "config" {
		t.Fatalf("NewConfig must clone its input: %q", service)
	}
}

func TestSchemaRootReturnsClone(t *testing.T) {
	t.Parallel()
	schema := config.ComposeSchema(config.AppBlockSchema())
	root := schema.Root()
	root["type"] = "mutated"
	if schema.Root()["type"] != "object" {
		t.Fatal("Schema.Root must return an independent clone")
	}
}

func TestBytesSourceClonesContent(t *testing.T) {
	t.Parallel()
	content := []byte("a: 1")
	source := config.NewBytesYAMLSource("x", content)
	content[0] = 'b'
	got, err := source.Read(context.Background())
	if err != nil || string(got) != "a: 1" {
		t.Fatalf("NewBytesYAMLSource must clone content: %q %v", got, err)
	}
}

func TestMapEnvSourceClonesVars(t *testing.T) {
	t.Parallel()
	vars := map[string]string{"K": "V"}
	source := config.NewMapEnvSource("x", vars)
	vars["K"] = "mutated"
	got, err := source.Environ(context.Background())
	if err != nil || got["K"] != "V" {
		t.Fatalf("NewMapEnvSource must clone vars: %v %v", got, err)
	}
}

func TestNewBlockClonesFragment(t *testing.T) {
	t.Parallel()
	fragment := map[string]any{"type": "object"}
	block := config.NewBlock("k", true, fragment)
	fragment["type"] = "mutated"
	if block.Schema["type"] != "object" {
		t.Fatal("NewBlock must clone its fragment")
	}
}
