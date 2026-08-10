package config_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
)

func TestBytesYAMLSource(t *testing.T) {
	t.Parallel()
	source := config.NewBytesYAMLSource("inline", []byte("a: 1"))
	if source.Name() != "inline" {
		t.Fatalf("name: %q", source.Name())
	}
	content, err := source.Read(context.Background())
	if err != nil || string(content) != "a: 1" {
		t.Fatalf("read: %q %v", content, err)
	}
}

func TestFileYAMLSourceReadsAndReportsPath(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	path := filepath.Join(dir, "settings.yaml")
	if err := os.WriteFile(path, []byte("a: 1"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	source := config.NewFileYAMLSource("base", path)
	if source.Path() != path || source.Name() != "base" {
		t.Fatalf("metadata: %q %q", source.Path(), source.Name())
	}
	content, err := source.Read(context.Background())
	if err != nil || string(content) != "a: 1" {
		t.Fatalf("read: %q %v", content, err)
	}
}

func TestFileYAMLSourceRequiredMissingErrors(t *testing.T) {
	t.Parallel()
	source := config.NewFileYAMLSource("base", filepath.Join(t.TempDir(), "absent.yaml"))
	if _, err := source.Read(context.Background()); err == nil {
		t.Fatal("a missing required file must error")
	}
}

func TestFileYAMLSourceOptionalMissingIsAbsent(t *testing.T) {
	t.Parallel()
	source := config.NewOptionalFileYAMLSource("overlay", filepath.Join(t.TempDir(), "absent.yaml"))
	content, err := source.Read(context.Background())
	if err != nil || content != nil {
		t.Fatalf("absent optional file must yield (nil, nil), got %q %v", content, err)
	}
}

func TestOSEnvSourceReadsProcessEnvironment(t *testing.T) {
	t.Setenv("DIENE_CONFIG_PROBE", "present")
	source := config.NewOSEnvSource()
	if source.Name() != "process-environment" {
		t.Fatalf("name: %q", source.Name())
	}
	environment, err := source.Environ(context.Background())
	if err != nil {
		t.Fatalf("environ: %v", err)
	}
	if environment["DIENE_CONFIG_PROBE"] != "present" {
		t.Fatalf("process env not read: %v", environment["DIENE_CONFIG_PROBE"])
	}
}

func TestMapEnvSource(t *testing.T) {
	t.Parallel()
	source := config.NewMapEnvSource("fake", map[string]string{"K": "V"})
	if source.Name() != "fake" {
		t.Fatalf("name: %q", source.Name())
	}
	environment, err := source.Environ(context.Background())
	if err != nil || environment["K"] != "V" {
		t.Fatalf("environ: %v %v", environment, err)
	}
}
