package fixture_test

import (
	"testing"
	"time"

	interfacesth "github.com/AtomiCloud/diene.go-interfaces/testhelper"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/fixture"
)

func TestNewBuilderNeedsAProblemFactory(t *testing.T) {
	t.Parallel()

	_, err := fixture.NewBuilder(nil).WithBlock("otel", map[string]any{}).Build()
	if err == nil || err.Error() != "fixture: problems is required" {
		t.Fatalf("Build() error = %v, want the unconfigured message", err)
	}
}

func TestWithAppWritesTheServiceTree(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithApp(sampleApp())
	})
	app, valid := bundle.Base[config.AppKey].(map[string]any)
	if !valid {
		t.Fatalf("base = %v, want an app block", bundle.Base)
	}
	want := map[string]any{
		"landscape": "garden", "platform": "sulfoxide",
		"service": "billing", "module": "core", "version": "1.0.0",
	}
	for key, value := range want {
		if app[key] != value {
			t.Fatalf("app[%q] = %v, want %v", key, app[key], value)
		}
	}
}

func TestBuildIsIndependentOfTheBuilder(t *testing.T) {
	t.Parallel()

	builder := fixture.NewBuilder(requireProblems(t)).
		WithBlock("otel", map[string]any{"logs": map[string]any{"enabled": true}}).
		WithOverlay("garden", "otel", map[string]any{"logs": map[string]any{"enabled": false}}).
		WithEnv("otel.logs.enabled", "true").
		WithList("api.scopes", []string{"read", "write"})
	bundle, err := builder.Build()
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	builder.WithBlock("otel", map[string]any{"logs": map[string]any{"enabled": "mutated"}})
	builder.WithEnv("otel.logs.enabled", "mutated")
	builder.WithList("api.scopes", []string{"mutated"})

	otelBlock, valid := bundle.Base["otel"].(map[string]any)
	if !valid {
		t.Fatalf("base = %v, want the otel block", bundle.Base)
	}
	logs, valid := otelBlock["logs"].(map[string]any)
	if enabled, marked := logs["enabled"].(bool); !valid || !marked || !enabled {
		t.Fatalf("otel block = %v, want the built value preserved", otelBlock)
	}
	if bundle.Env["otel.logs.enabled"] != "true" {
		t.Fatalf("env = %v, want the built value preserved", bundle.Env)
	}
	if len(bundle.Lists["api.scopes"]) != 2 || bundle.Lists["api.scopes"][0] != "read" {
		t.Fatalf("lists = %v, want the built values preserved", bundle.Lists)
	}
}

func TestBuilderRefusesBlankIdentifiers(t *testing.T) {
	t.Parallel()

	cases := map[string]func(*fixture.Builder) *fixture.Builder{
		"block key":         func(b *fixture.Builder) *fixture.Builder { return b.WithBlock("  ", map[string]any{}) },
		"overlay landscape": func(b *fixture.Builder) *fixture.Builder { return b.WithOverlay("", "otel", map[string]any{}) },
		"overlay block key": func(b *fixture.Builder) *fixture.Builder { return b.WithOverlay("garden", "", map[string]any{}) },
		"environment path":  func(b *fixture.Builder) *fixture.Builder { return b.WithEnv("", "value") },
		"list path":         func(b *fixture.Builder) *fixture.Builder { return b.WithList("", []string{"one"}) },
		"secret path":       func(b *fixture.Builder) *fixture.Builder { return b.WithSecret("", "value") },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			_, err := mutate(fixture.NewBuilder(requireProblems(t))).Build()
			if got := problemID(t, err); got != e2e.ProblemFixtureInvalid {
				t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureInvalid)
			}
		})
	}
}

func TestBuilderRefusesTheBaseLayerAsAnOverlay(t *testing.T) {
	t.Parallel()

	_, err := fixture.NewBuilder(requireProblems(t)).
		WithOverlay(config.BaseLandscape, "otel", map[string]any{}).
		Build()
	if got := problemID(t, err); got != e2e.ProblemFixtureInvalid {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureInvalid)
	}
}

func TestBuilderKeepsOnlyTheFirstFailure(t *testing.T) {
	t.Parallel()

	_, err := fixture.NewBuilder(requireProblems(t)).
		WithBlock("", map[string]any{}).
		WithEnv("", "").
		WithList("", nil).
		WithSecret("", "").
		WithOverlay("", "", nil).
		Build()
	if got := problemID(t, err); got != e2e.ProblemFixtureInvalid {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureInvalid)
	}
}

func TestWithSecretBlanksTheDocumentAndInjectsTheEnvironment(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.
			WithBlock("postgres", map[string]any{"MAIN": map[string]any{"host": "db.invalid"}}).
			WithSecret("postgres.MAIN.password", "injected")
	})
	block, valid := bundle.Base["postgres"].(map[string]any)
	if !valid {
		t.Fatalf("base = %v, want the postgres block", bundle.Base)
	}
	entry, valid := block["MAIN"].(map[string]any)
	if !valid {
		t.Fatalf("postgres block = %v, want the MAIN entry", block)
	}
	if entry["password"] != "" {
		t.Fatalf("password = %v, want a blank document value", entry["password"])
	}
	if entry["host"] != "db.invalid" {
		t.Fatalf("host = %v, want the existing value preserved", entry["host"])
	}
	if bundle.Env["postgres.MAIN.password"] != "injected" {
		t.Fatalf("env = %v, want the secret injected through the environment", bundle.Env)
	}
}

func TestWithSecretCreatesMissingIntermediateLevels(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.WithSecret("storage.ASSETS.secretAccessKey", "shhh")
	})
	storage, valid := bundle.Base["storage"].(map[string]any)
	if !valid {
		t.Fatalf("base = %v, want the storage level created", bundle.Base)
	}
	assets, valid := storage["ASSETS"].(map[string]any)
	if !valid {
		t.Fatalf("storage = %v, want the ASSETS level created", storage)
	}
	if assets["secretAccessKey"] != "" {
		t.Fatalf("secret = %v, want a blank document value", assets["secretAccessKey"])
	}
}

func TestWithSecretOverwritesANonMapIntermediateLevel(t *testing.T) {
	t.Parallel()

	bundle := requireBundle(t, func(builder *fixture.Builder) *fixture.Builder {
		return builder.
			WithBlock("cache", map[string]any{"MAIN": "not-a-map"}).
			WithSecret("cache.MAIN.password", "injected")
	})
	cache, valid := bundle.Base["cache"].(map[string]any)
	if !valid {
		t.Fatalf("base = %v, want the cache block", bundle.Base)
	}
	entry, valid := cache["MAIN"].(map[string]any)
	if !valid {
		t.Fatalf("cache = %v, want the scalar replaced by a level", cache)
	}
	if entry["password"] != "" {
		t.Fatalf("password = %v, want a blank document value", entry["password"])
	}
}

func TestWithSecretRefusesABlankValue(t *testing.T) {
	t.Parallel()

	_, err := fixture.NewBuilder(requireProblems(t)).WithSecret("postgres.MAIN.password", "").Build()
	if got := problemID(t, err); got != e2e.ProblemFixtureInvalid {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemFixtureInvalid)
	}
}

func TestWireHelpersEnforceTheC0Codecs(t *testing.T) {
	t.Parallel()

	if _, err := fixture.Duration("PT30S"); err != nil {
		t.Fatalf("Duration() error = %v, want an ISO 8601 duration accepted", err)
	}
	if _, err := fixture.Duration("30s"); err == nil {
		t.Fatal("Duration() error = nil, want a non-ISO duration refused")
	}
	if got, err := fixture.Zone("Asia/Singapore"); err != nil || got != "Asia/Singapore" {
		t.Fatalf("Zone() = %q, %v, want the IANA identifier accepted", got, err)
	}
	if _, err := fixture.Zone("+08:00"); err == nil {
		t.Fatal("Zone() error = nil, want an offset refused")
	}
}

func TestInstantNeedsASystemSeam(t *testing.T) {
	t.Parallel()

	if _, err := fixture.Instant(nil); err == nil {
		t.Fatal("Instant() error = nil, want the unconfigured refusal")
	}
}

func TestDirectorySlugsTheCaseName(t *testing.T) {
	t.Parallel()

	if got := fixture.Directory("/tmp/fixtures/", "Sign In Then Pay"); got != "/tmp/fixtures/sign-in-then-pay" {
		t.Fatalf("Directory() = %q, want the slugged path", got)
	}
	if got := fixture.Directory("/tmp/fixtures", "  "); got != "/tmp/fixtures" {
		t.Fatalf("Directory() = %q, want the root when the name slugs to nothing", got)
	}
}

func TestInstantRendersTheC0WireInstant(t *testing.T) {
	t.Parallel()

	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{
		Now: time.Date(2026, time.July, 26, 8, 30, 0, 0, time.UTC),
	})
	got, err := fixture.Instant(system)
	if err != nil {
		t.Fatalf("Instant() error = %v", err)
	}
	if got != "2026-07-26T08:30:00.000Z" {
		t.Fatalf("Instant() = %q, want the RFC 3339 UTC instant", got)
	}
}
