package fixture_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/fixture"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// errBoom is the arbitrary seam failure the filesystem mock is made to return.
var errBoom = errors.New("boom")

// requireProblems builds the harness problem factory or fails the test.
func requireProblems(t *testing.T) *e2e.Problems {
	t.Helper()
	problems, err := e2e.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		t.Fatalf("NewProblems() error = %v", err)
	}
	return problems
}

// sampleApp is the service-tree identity every fixture test builds around.
func sampleApp() config.AppBlock {
	return config.AppBlock{
		Landscape: "garden",
		Platform:  "sulfoxide",
		Service:   "billing",
		Module:    "core",
		Version:   "1.0.0",
	}
}

// requireBundle builds a fixture or fails the test.
func requireBundle(t *testing.T, build func(*fixture.Builder) *fixture.Builder) fixture.Bundle {
	t.Helper()
	builder := fixture.NewBuilder(requireProblems(t))
	if build != nil {
		builder = build(builder)
	}
	bundle, err := builder.Build()
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	return bundle
}

// problemID extracts the trailing id segment of a problem type URI.
func problemID(t *testing.T, err error) string {
	t.Helper()
	if err == nil {
		t.Fatal("expected a problem-typed error, got nil")
	}
	var typed *problem.Error
	if !errors.As(err, &typed) {
		t.Fatalf("expected a problem-typed error, got %v", err)
	}
	index := strings.LastIndex(typed.Problem.Type, "/")
	return typed.Problem.Type[index+1:]
}

// unmarshalable is a value YAML cannot render, which is how the render-failure
// path is reached without reaching into the package.
func unmarshalable() map[string]any {
	return map[string]any{"callback": func() {}}
}
