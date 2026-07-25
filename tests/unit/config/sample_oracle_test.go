package config_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"gopkg.in/yaml.v3"
)

// repoRoot resolves the module root from this test package directory.
const repoRoot = "../../.."

type sampleAppSection struct {
	Platform string `yaml:"platform"`
}

type sampleCacheSection struct {
	Secret string `yaml:"secret"`
}

type sampleServiceSection struct {
	Cache sampleCacheSection `yaml:"cache"`
}

type sampleDocument struct {
	App     sampleAppSection     `yaml:"app"`
	Service sampleServiceSection `yaml:"service"`
}

func readCommittedSchema(t *testing.T) config.Schema {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(repoRoot, "config", "config.schema.json"))
	if err != nil {
		t.Fatalf("read committed schema: %v", err)
	}
	schema, err := config.SchemaFromJSON(raw)
	if err != nil {
		t.Fatalf("parse committed schema: %v", err)
	}
	return schema
}

// TestCommittedYAMLDeclaresSchemaOnFirstLine is the structural half of the
// oracle: every committed config YAML must point at the schema on its first
// line, and that pointer must resolve to the committed artifact.
func TestCommittedYAMLDeclaresSchemaOnFirstLine(t *testing.T) {
	t.Parallel()
	cases := []struct {
		path    string
		pointer string
	}{
		{filepath.Join(repoRoot, "config", "app", "settings.yaml"), "../config.schema.json"},
		{filepath.Join(repoRoot, "config", "app", "settings.lapras.yaml"), "../config.schema.json"},
		{filepath.Join(repoRoot, "config", "dev.yaml"), "./config.schema.json"},
	}
	for _, sample := range cases {
		raw, err := os.ReadFile(sample.path)
		if err != nil {
			t.Fatalf("read %s: %v", sample.path, err)
		}
		firstLine, _, _ := strings.Cut(string(raw), "\n")
		want := "# yaml-language-server: $schema=" + sample.pointer
		if firstLine != want {
			t.Fatalf("%s first line = %q, want %q", sample.path, firstLine, want)
		}
		resolved := filepath.Join(filepath.Dir(sample.path), sample.pointer)
		if _, err := os.Stat(resolved); err != nil {
			t.Fatalf("%s schema pointer does not resolve to the artifact: %v", sample.path, err)
		}
	}
}

// TestCommittedSchemaHasExpectedStructure is the independent content oracle: it
// asserts the artifact's shape by hand rather than regenerating and diffing.
func TestCommittedSchemaHasExpectedStructure(t *testing.T) {
	t.Parallel()
	raw, err := os.ReadFile(filepath.Join(repoRoot, "config", "config.schema.json"))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var schema map[string]any
	if err := json.Unmarshal(raw, &schema); err != nil {
		t.Fatalf("committed schema must be valid JSON: %v", err)
	}
	if schema["$schema"] != config.Draft2020 || schema["type"] != "object" {
		t.Fatalf("committed schema must be a draft 2020-12 object schema: %v", schema["$schema"])
	}
	properties, ok := schema["properties"].(map[string]any)
	if !ok || properties["app"] == nil || properties["service"] == nil {
		t.Fatalf("committed schema must mount app and service blocks: %v", schema["properties"])
	}
	app, ok := properties["app"].(map[string]any)
	if !ok {
		t.Fatalf("app block must be an object: %v", properties["app"])
	}
	required, ok := app["required"].([]any)
	if !ok || len(required) != 5 {
		t.Fatalf("app block must require the full LPSMV tuple: %v", app["required"])
	}
}

// TestCommittedBaseAndOverlayValidateAgainstArtifact loads the committed base
// plus its sparse landscape overlay through the real loader and the shipped
// schema, proving the YAML and schema agree.
func TestCommittedBaseAndOverlayValidateAgainstArtifact(t *testing.T) {
	t.Parallel()
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseDir(filepath.Join(repoRoot, "config", "app")),
		config.WithLandscape("lapras"),
		config.WithEnvSource(config.NewMapEnvSource("empty", nil)),
		config.WithSchema(readCommittedSchema(t)),
	).Load(context.Background())
	if err != nil {
		t.Fatalf("committed base+overlay must validate: %v", err)
	}
	var host string
	if err := cfg.Decode("service.http.host", &host); err != nil {
		t.Fatalf("decode host: %v", err)
	}
	if host != "config.lapras.svc" {
		t.Fatalf("overlay host must win: %q", host)
	}
	var port int
	if err := cfg.Decode("service.http.port", &port); err != nil {
		t.Fatalf("decode port: %v", err)
	}
	if port != 8080 {
		t.Fatalf("base port must survive the sparse overlay: %d", port)
	}
}

// TestCommittedDevFileValidatesAgainstArtifact loads config/dev.yaml standalone
// against the shipped schema.
func TestCommittedDevFileValidatesAgainstArtifact(t *testing.T) {
	t.Parallel()
	devPath := filepath.Join(repoRoot, "config", "dev.yaml")
	cfg, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewFileYAMLSource("dev", devPath)),
		config.WithEnvSource(config.NewMapEnvSource("empty", nil)),
		config.WithSchema(readCommittedSchema(t)),
	).Load(context.Background())
	if err != nil {
		t.Fatalf("committed dev file must validate: %v", err)
	}
	app, err := cfg.App()
	if err != nil {
		t.Fatalf("app: %v", err)
	}
	if app.Version != "0.0.0-dev" {
		t.Fatalf("dev version wrong: %q", app.Version)
	}
}

// TestCommittedBaseParsesIndependently cross-checks the base document with a
// second YAML parser, so the oracle does not rely solely on the loader's viper.
func TestCommittedBaseParsesIndependently(t *testing.T) {
	t.Parallel()
	raw, err := os.ReadFile(filepath.Join(repoRoot, "config", "app", "settings.yaml"))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var document sampleDocument
	if err := yaml.Unmarshal(raw, &document); err != nil {
		t.Fatalf("independent parse: %v", err)
	}
	if document.App.Platform != "sulfoxide" {
		t.Fatalf("unexpected platform: %q", document.App.Platform)
	}
	if document.Service.Cache.Secret != "" {
		t.Fatal("committed secret example must be blank")
	}
}
