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
