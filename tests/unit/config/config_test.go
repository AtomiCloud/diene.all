package config_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
)

func TestRawReturnsAnIndependentClone(t *testing.T) {
	t.Parallel()
	cfg := config.NewConfig(map[string]any{"app": map[string]any{"service": "config"}})
	clone := cfg.Raw()
	clone["app"].(map[string]any)["service"] = "mutated"
	fresh := cfg.Raw()
	if fresh["app"].(map[string]any)["service"] != "config" {
		t.Fatalf("Raw must return an independent clone: %v", fresh)
	}
}

func TestDecodeTypedSlice(t *testing.T) {
	t.Parallel()
	cfg := config.NewConfig(map[string]any{"demo": map[string]any{"replicas": []any{1, 2, 3}}})
	var replicas []int
	if err := cfg.Decode("demo.replicas", &replicas); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(replicas) != 3 || replicas[2] != 3 {
		t.Fatalf("typed slice decode wrong: %v", replicas)
	}
}

func TestDecodeMatchesKeysAcrossCasings(t *testing.T) {
	t.Parallel()
	// The stored keys use Pascal and kebab spellings; a snake dotted lookup must
	// still resolve them.
	cfg := config.NewConfig(map[string]any{"App": map[string]any{"Land-Scape": "lapras"}})
	var landscape string
	if err := cfg.Decode("app.landscape", &landscape); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if landscape != "lapras" {
		t.Fatalf("casing-insensitive lookup failed: %q", landscape)
	}
}

func TestDecodeMissingKeyErrors(t *testing.T) {
	t.Parallel()
	cfg := config.NewConfig(map[string]any{})
	if err := cfg.Decode("nope", new(string)); err == nil {
		t.Fatal("a missing key must error")
	}
}

func TestDecodeThroughScalarMidPathErrors(t *testing.T) {
	t.Parallel()
	cfg := config.NewConfig(map[string]any{"app": "scalar"})
	if err := cfg.Decode("app.landscape", new(string)); err == nil {
		t.Fatal("descending through a scalar must error")
	}
}

func TestDecodeUnencodableSubtreeErrors(t *testing.T) {
	t.Parallel()
	cfg := config.NewConfig(map[string]any{"bad": make(chan int)})
	if err := cfg.Decode("bad", new(any)); err == nil {
		t.Fatal("an unencodable subtree must error")
	}
}

func TestAppDecodesServiceTreeBlock(t *testing.T) {
	t.Parallel()
	cfg := config.NewConfig(map[string]any{"app": map[string]any{
		"landscape": "lapras", "platform": "sulfoxide",
		"service": "config", "module": "lib", "version": "1.0.0",
	}})
	app, err := cfg.App()
	if err != nil {
		t.Fatalf("app: %v", err)
	}
	if app.Landscape != "lapras" || app.Version != "1.0.0" {
		t.Fatalf("app block wrong: %+v", app)
	}
}

func TestAppMissingBlockErrors(t *testing.T) {
	t.Parallel()
	if _, err := config.NewConfig(map[string]any{}).App(); err == nil {
		t.Fatal("a missing app block must error")
	}
}
