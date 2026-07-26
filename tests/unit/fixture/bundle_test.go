package fixture_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/fixture"
	"github.com/AtomiCloud/diene.go-e2e/lib/preview"
	interfacesth "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// layered is the R14 fixture the bundle tests exercise: full base defaults, a
// sparse landscape overlay, and an environment layer.
func layered(t *testing.T) fixture.Bundle {
	t.Helper()
	return requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.
			WithApp(sampleApp()).
			WithBlock("postgres", map[string]any{"MAIN": map[string]any{
				"host": "postgres.invalid", "port": 5432, "database": "billing", "ssl": false,
			}}).
			WithOverlay("garden", "postgres", map[string]any{"MAIN": map[string]any{
				"host": "primary.garden.invalid", "ssl": true,
			}}).
			WithSecret("postgres.MAIN.password", "injected").
			WithList("api.scopes", []string{"read", "write"})
	})
}

func TestLandscapesAreStable(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.
			WithOverlay("pichu", "otel", map[string]any{}).
			WithOverlay("garden", "otel", map[string]any{}).
			WithOverlay("lapras", "otel", map[string]any{})
	})
	got := bundle.Landscapes()
	want := []string{"garden", "lapras", "pichu"}
	if len(got) != len(want) {
		t.Fatalf("Landscapes() = %v, want %v", got, want)
	}
	for index, landscape := range want {
		if got[index] != landscape {
			t.Fatalf("Landscapes() = %v, want %v", got, want)
		}
	}
}

func TestMergedAppliesTheSparseOverlayAndKeepsBaseDefaults(t *testing.T) {
	t.Parallel()

	merged := layered(t).Merged("garden")
	postgres, valid := merged["postgres"].(map[string]any)
	if !valid {
		t.Fatalf("merged = %v, want the postgres block", merged)
	}
	entry, valid := postgres["MAIN"].(map[string]any)
	if !valid {
		t.Fatalf("postgres = %v, want the MAIN entry", postgres)
	}
	if entry["host"] != "primary.garden.invalid" {
		t.Fatalf("host = %v, want the overlay value", entry["host"])
	}
	if ssl, marked := entry["ssl"].(bool); !marked || !ssl {
		t.Fatalf("ssl = %v, want the overlay to flip the posture", entry["ssl"])
	}
	if entry["database"] != "billing" || entry["port"] != 5432 {
		t.Fatalf("entry = %v, want the sparse overlay to leave base defaults alone", entry)
	}
	if entry["password"] != "" {
		t.Fatalf("password = %v, want the document secret to stay blank", entry["password"])
	}
}

func TestMergedIgnoresAnUnknownLandscape(t *testing.T) {
	t.Parallel()

	merged := layered(t).Merged("no-such-landscape")
	postgres, valid := merged["postgres"].(map[string]any)
	if !valid {
		t.Fatalf("merged = %v, want the postgres block", merged)
	}
	entry, valid := postgres["MAIN"].(map[string]any)
	if !valid {
		t.Fatalf("postgres = %v, want the MAIN entry", postgres)
	}
	if entry["host"] != "postgres.invalid" {
		t.Fatalf("host = %v, want the base value", entry["host"])
	}
}

func TestDocumentRendersEachLayer(t *testing.T) {
	t.Parallel()

	bundle := layered(t)
	base, err := bundle.Document(config.BaseLandscape)
	if err != nil {
		t.Fatalf("Document(base) error = %v", err)
	}
	if !strings.Contains(string(base), "postgres.invalid") {
		t.Fatalf("base document = %q, want the base defaults", base)
	}
	overlay, err := bundle.Document("garden")
	if err != nil {
		t.Fatalf("Document(garden) error = %v", err)
	}
	if !strings.Contains(string(overlay), "primary.garden.invalid") {
		t.Fatalf("overlay document = %q, want the overlay value", overlay)
	}
	if strings.Contains(string(overlay), "database") {
		t.Fatalf("overlay document = %q, want it to stay sparse", overlay)
	}
	absent, err := bundle.Document("no-such-landscape")
	if err != nil {
		t.Fatalf("Document(absent) error = %v", err)
	}
	if strings.TrimSpace(string(absent)) != "{}" {
		t.Fatalf("absent overlay = %q, want an empty document", absent)
	}
}

func TestDocumentReportsAnUnrenderableLayer(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithBlock("broken", unmarshalable())
	})
	if _, err := bundle.Document(config.BaseLandscape); err == nil {
		t.Fatal("Document() error = nil, want a render refusal")
	}
}

func TestEnvironRendersTheC0Shape(t *testing.T) {
	t.Parallel()

	environ := layered(t).Environ("")
	if got := environ["ATOMI_POSTGRES__MAIN__PASSWORD"]; got != "injected" {
		t.Fatalf("environ = %v, want the nested secret under the default prefix", environ)
	}
	if got := environ["ATOMI_API__SCOPES__0"]; got != "read" {
		t.Fatalf("environ = %v, want the first indexed list entry", environ)
	}
	if got := environ["ATOMI_API__SCOPES__1"]; got != "write" {
		t.Fatalf("environ = %v, want the second indexed list entry", environ)
	}
	if _, found := environ["ATOMI_API__SCOPES"]; found {
		t.Fatalf("environ = %v, want no joined collection value", environ)
	}
	custom := layered(t).Environ("DIENE_")
	if got := custom["DIENE_POSTGRES__MAIN__PASSWORD"]; got != "injected" {
		t.Fatalf("environ = %v, want the configured prefix honoured", custom)
	}
}

func TestEnvironEmitsNothingForAnEmptyCollection(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithList("api.scopes", nil)
	})
	environ := bundle.Environ(fixture.DefaultEnvPrefix)
	if len(environ) != 0 {
		t.Fatalf("environ = %v, want nothing emitted for an empty collection", environ)
	}
}

func TestEnvKeyIsTheOneEncoding(t *testing.T) {
	t.Parallel()

	if got := fixture.EnvKey("ATOMI_", "postgres.MAIN.pool.max"); got != "ATOMI_POSTGRES__MAIN__POOL__MAX" {
		t.Fatalf("EnvKey() = %q, want the C0 nesting", got)
	}
	if got := fixture.EnvKey("ATOMI_", "otel"); got != "ATOMI_OTEL" {
		t.Fatalf("EnvKey() = %q, want a single segment untouched", got)
	}
}

func TestMaterializeWritesEveryLayerThroughTheSeam(t *testing.T) {
	t.Parallel()

	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	layout, err := layered(t).Materialize(context.Background(), filesystem, "/tmp/case", requireProblems(t))
	if err != nil {
		t.Fatalf("Materialize() error = %v", err)
	}
	if layout.Directory != "/tmp/case" {
		t.Fatalf("directory = %q, want /tmp/case", layout.Directory)
	}
	if layout.BasePath != "/tmp/case/base.yaml" {
		t.Fatalf("base path = %q, want the base document", layout.BasePath)
	}
	if layout.OverlayPaths["garden"] != "/tmp/case/garden.yaml" {
		t.Fatalf("overlay paths = %v, want the garden overlay", layout.OverlayPaths)
	}
	files := filesystem.Files()
	if !strings.Contains(string(files[layout.BasePath]), "postgres.invalid") {
		t.Fatalf("base file = %q, want the base defaults on disk", files[layout.BasePath])
	}
	if !strings.Contains(string(files[layout.OverlayPaths["garden"]]), "primary.garden.invalid") {
		t.Fatalf("overlay file = %q, want the overlay on disk", files[layout.OverlayPaths["garden"]])
	}
}

func TestMaterializeRefusesMissingSeams(t *testing.T) {
	t.Parallel()

	bundle := layered(t)
	if _, err := bundle.Materialize(context.Background(), nil, "/tmp/case", nil); err == nil {
		t.Fatal("Materialize() error = nil, want the unconfigured refusal")
	}
	_, err := bundle.Materialize(context.Background(), nil, "/tmp/case", requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemFixtureUnwritable {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureUnwritable)
	}
	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	_, err = bundle.Materialize(context.Background(), filesystem, "   ", requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemFixtureUnwritable {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureUnwritable)
	}
}

func TestMaterializeReportsSeamFailures(t *testing.T) {
	t.Parallel()

	bundle := layered(t)

	directoryFailure := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	directoryFailure.EnqueueCreateDirectoryResult(errBoom)
	_, err := bundle.Materialize(context.Background(), directoryFailure, "/tmp/case", requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemFixtureUnwritable {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureUnwritable)
	}

	baseFailure := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	baseFailure.EnqueueWriteBytesResult(errBoom)
	_, err = bundle.Materialize(context.Background(), baseFailure, "/tmp/case", requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemFixtureUnwritable {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureUnwritable)
	}

	overlayFailure := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	overlayFailure.EnqueueWriteBytesResult(nil)
	overlayFailure.EnqueueWriteBytesResult(errBoom)
	_, err = bundle.Materialize(context.Background(), overlayFailure, "/tmp/case", requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemFixtureUnwritable {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureUnwritable)
	}
}

func TestMaterializeReportsAnUnrenderableLayer(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithBlock("broken", unmarshalable())
	})
	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	_, err := bundle.Materialize(context.Background(), filesystem, "/tmp/case", requireProblems(t))
	if got := problemID(t, err); got != e2e.ProblemFixtureInvalid {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureInvalid)
	}
}

// validFixture is the fixture that satisfies the composed preview root schema,
// so the loader assertions below prove a REAL three-layer load rather than a
// shape the validator never saw.
func validFixture(t *testing.T) fixture.Bundle {
	t.Helper()
	return requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.
			WithApp(sampleApp()).
			WithBlock("otel", otelDocument()).
			WithBlock("auth", authDocument()).
			WithBlock("api", apiDocument("https://billing.garden.invalid")).
			WithOverlay("garden", "api", map[string]any{
				"backends": map[string]any{"primary": map[string]any{
					"baseUrl": "https://billing.garden.overlay.invalid",
				}},
			}).
			WithEnv("app.version", "9.9.9")
	})
}

func TestLoaderLoadsTheMaterializedThreeLayerFixture(t *testing.T) {
	t.Parallel()

	bundle := validFixture(t)
	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	layout, err := bundle.Materialize(context.Background(), filesystem, "/tmp/valid", requireProblems(t))
	if err != nil {
		t.Fatalf("Materialize() error = %v", err)
	}
	// The in-memory seam is not the OS filesystem the config lib's file source
	// reads, so the loader is pointed at the bundle's own in-memory sources here
	// and at real paths in the integration tier.
	loader, err := bundle.Loader(fixture.LoaderOptions{
		Landscape: "garden",
		Schema:    preview.Schema(),
	})
	if err != nil {
		t.Fatalf("Loader() error = %v", err)
	}
	loaded, err := loader.Load(context.Background())
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	var app config.AppBlock
	if err := loaded.Decode(config.AppKey, &app); err != nil {
		t.Fatalf("Decode(app) error = %v", err)
	}
	if app.Version != "9.9.9" {
		t.Fatalf("app version = %q, want the environment layer to land last", app.Version)
	}
	if app.Service != "billing" {
		t.Fatalf("app service = %q, want the base default preserved", app.Service)
	}
	if layout.BasePath == "" {
		t.Fatalf("layout = %+v, want a materialized base path", layout)
	}
}

func TestLoaderReportsAnUnrenderableLayer(t *testing.T) {
	t.Parallel()

	broken := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithBlock("broken", unmarshalable())
	})
	if _, err := broken.Loader(fixture.LoaderOptions{Landscape: "garden"}); err == nil {
		t.Fatal("Loader() error = nil, want the base render refusal")
	}
	overlayBroken := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithOverlay("garden", "broken", unmarshalable())
	})
	if _, err := overlayBroken.Loader(fixture.LoaderOptions{Landscape: "garden"}); err == nil {
		t.Fatal("Loader() error = nil, want the overlay render refusal")
	}
}

func TestLoaderReadsTheMaterializedFilesWhenGivenALayout(t *testing.T) {
	t.Parallel()

	bundle := validFixture(t)
	directory := t.TempDir()
	layout := fixture.Layout{
		Directory:    directory,
		BasePath:     filepath.Join(directory, "base.yaml"),
		OverlayPaths: map[string]string{"garden": filepath.Join(directory, "garden.yaml")},
	}
	writeLayer(t, bundle, config.BaseLandscape, layout.BasePath)
	writeLayer(t, bundle, "garden", layout.OverlayPaths["garden"])

	loader, err := bundle.Loader(fixture.LoaderOptions{
		Layout:    layout,
		Landscape: "garden",
		Schema:    preview.Schema(),
		EnvPrefix: "ATOMI_",
	})
	if err != nil {
		t.Fatalf("Loader() error = %v", err)
	}
	loaded, err := loader.Load(context.Background())
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	var app config.AppBlock
	if err := loaded.Decode(config.AppKey, &app); err != nil {
		t.Fatalf("Decode(app) error = %v", err)
	}
	if app.Version != "9.9.9" {
		t.Fatalf("app version = %q, want the environment layer to land last", app.Version)
	}
	if app.Service != "billing" {
		t.Fatalf("app service = %q, want the base document read off disk", app.Service)
	}
}

// writeLayer puts one rendered layer on the real filesystem, which is what the
// file-source branch of the loader reads.
func writeLayer(t *testing.T, bundle fixture.Bundle, landscape string, target string) {
	t.Helper()
	document, err := bundle.Document(landscape)
	if err != nil {
		t.Fatalf("Document(%q) error = %v", landscape, err)
	}
	if err := os.WriteFile(target, document, 0o600); err != nil {
		t.Fatalf("WriteFile(%q) error = %v", target, err)
	}
}

func TestUnrenderableErrorNamesTheReason(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithBlock("broken", unmarshalable())
	})
	_, err := bundle.Document(config.BaseLandscape)
	var unrenderable *fixture.UnrenderableError
	if !errors.As(err, &unrenderable) {
		t.Fatalf("Document() error = %v, want an UnrenderableError", err)
	}
	if !strings.Contains(unrenderable.Error(), "cannot be rendered as YAML") {
		t.Fatalf("Error() = %q, want the render refusal described", unrenderable.Error())
	}
	if !strings.Contains(unrenderable.Reason, "cannot marshal type") {
		t.Fatalf("Reason = %q, want the encoder's own objection", unrenderable.Reason)
	}
}
