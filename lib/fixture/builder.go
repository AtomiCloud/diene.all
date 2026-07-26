package fixture

import (
	"errors"
	"maps"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// Builder accumulates the layers of a fixture and refuses the ones a harness
// must not emit.
//
// It collects errors rather than returning one per call, so a fixture reads as
// a single chained declaration and still fails on the first thing wrong with it
// when [Builder.Build] runs.
type Builder struct {
	problems *e2e.Problems
	base     map[string]any
	overlays map[string]map[string]any
	env      map[string]string
	lists    map[string][]string
	failure  error
}

// NewBuilder starts an empty fixture.
func NewBuilder(problems *e2e.Problems) *Builder {
	builder := &Builder{
		problems: problems,
		base:     map[string]any{},
		overlays: map[string]map[string]any{},
		env:      map[string]string{},
		lists:    map[string][]string{},
		failure:  nil,
	}
	if problems == nil {
		builder.failure = errUnconfigured("problems")
	}
	return builder
}

// WithApp sets the fixture's `app:` block from a service-tree identity.
func (b *Builder) WithApp(app config.AppBlock) *Builder {
	return b.WithBlock(config.AppKey, map[string]any{
		"landscape": app.Landscape,
		"platform":  app.Platform,
		"service":   app.Service,
		"module":    app.Module,
		"version":   app.Version,
	})
}

// WithBlock sets one engine block in the full-defaults base layer.
func (b *Builder) WithBlock(key string, value map[string]any) *Builder {
	if b.reject(key, "block key") {
		return b
	}
	b.base[key] = value
	return b
}

// WithOverlay sets one engine block in a sparse landscape overlay.
//
// The overlay is SPARSE by contract: whatever it does not mention keeps the base
// value, which is what makes a landscape diff readable.
func (b *Builder) WithOverlay(landscape string, key string, value map[string]any) *Builder {
	if b.reject(landscape, "overlay landscape") || b.reject(key, "block key") {
		return b
	}
	if landscape == config.BaseLandscape {
		b.fail("an overlay landscape cannot be the base layer", map[string]any{"landscape": landscape})
		return b
	}
	overlay, found := b.overlays[landscape]
	if !found {
		overlay = map[string]any{}
		b.overlays[landscape] = overlay
	}
	overlay[key] = value
	return b
}

// WithEnv sets one scalar in the environment layer, addressed by its dotted
// configuration path.
func (b *Builder) WithEnv(key string, value string) *Builder {
	if b.reject(key, "environment path") {
		return b
	}
	b.env[key] = value
	return b
}

// WithList sets one collection in the environment layer, which
// [Bundle.Environ] renders as C0 indexed keys.
func (b *Builder) WithList(key string, values []string) *Builder {
	if b.reject(key, "environment path") {
		return b
	}
	b.lists[key] = values
	return b
}

// WithSecret sets a secret: blank in the YAML layer, injected through the
// environment layer.
//
// This pairing is the point. A secret written into a base document is a secret
// in a repository the moment a consumer copies the fixture, so the harness makes
// the safe shape the easy one and never offers the unsafe one.
func (b *Builder) WithSecret(key string, value string) *Builder {
	if b.reject(key, "secret path") {
		return b
	}
	if value == "" {
		b.fail("a secret with a blank value is indistinguishable from an unset one", map[string]any{"path": key})
		return b
	}
	segments := strings.Split(key, PathSeparator)
	cursor := b.base
	for _, segment := range segments[:len(segments)-1] {
		nested, found := cursor[segment].(map[string]any)
		if !found {
			nested = map[string]any{}
			cursor[segment] = nested
		}
		cursor = nested
	}
	cursor[segments[len(segments)-1]] = ""
	b.env[key] = value
	return b
}

// Build returns the accumulated fixture, or the first thing wrong with it.
func (b *Builder) Build() (Bundle, error) {
	if b.failure != nil {
		return Bundle{}, b.failure
	}
	return Bundle{
		Base:     cloneDocument(b.base),
		Overlays: cloneOverlays(b.overlays),
		Env:      cloneStrings(b.env),
		Lists:    cloneLists(b.lists),
	}, nil
}

// reject records a blank identifier and reports whether the caller should stop.
func (b *Builder) reject(value string, label string) bool {
	if b.failure != nil {
		return true
	}
	if strings.TrimSpace(value) == "" {
		b.fail("a fixture needs a non-blank "+label, map[string]any{"field": label})
		return true
	}
	return false
}

// fail records the invalid-fixture problem.
//
// Every call site is behind [Builder.reject], which already stops once a failure
// is recorded, so this never overwrites an earlier one and never runs with a nil
// problem factory.
func (b *Builder) fail(detail string, data map[string]any) {
	b.failure = b.problems.Raise(e2e.ProblemFixtureInvalid, detail, data)
}

// cloneDocument deep-copies one configuration layer.
//
// It goes through the core-utils merge of a single layer rather than a bare
// DeepClone plus a type assertion: the merge is already typed as a document, so
// there is no assertion to get wrong and no unreachable fallback to pretend to
// test.
func cloneDocument(source map[string]any) map[string]any {
	return coreutils.DeepMergeAll(source)
}

// cloneOverlays deep-copies the overlay layers so a built bundle cannot be
// mutated through the builder that produced it.
func cloneOverlays(source map[string]map[string]any) map[string]map[string]any {
	cloned := make(map[string]map[string]any, len(source))
	for landscape, overlay := range source {
		cloned[landscape] = cloneDocument(overlay)
	}
	return cloned
}

// cloneStrings copies a scalar map.
func cloneStrings(source map[string]string) map[string]string {
	cloned := make(map[string]string, len(source))
	maps.Copy(cloned, source)
	return cloned
}

// cloneLists copies a collection map.
func cloneLists(source map[string][]string) map[string][]string {
	cloned := make(map[string][]string, len(source))
	for key, values := range source {
		cloned[key] = append([]string(nil), values...)
	}
	return cloned
}

// errUnconfigured reports a seam the package cannot substitute for and cannot
// describe as a problem either, because the problem factory is what is missing.
func errUnconfigured(component string) error {
	return errors.New("fixture: " + component + " is required")
}

// Instant renders the current time as a C0 §1 RFC 3339 UTC instant, read
// through the system seam so a fixture is reproducible.
func Instant(system interfaces.System) (string, error) {
	if system == nil {
		return "", errUnconfigured("system")
	}
	return coreutils.NowWireInstant(system)
}

// Duration renders an ISO 8601 duration string, rejecting anything C0 does not
// accept.
//
// A fixture that wrote "30s" would be accepted by some readers and rejected by
// others, which is exactly the cross-language drift C0 §1 forbids.
func Duration(value string) (string, error) {
	parsed, err := coreutils.ParseIsoDuration(value)
	if err != nil {
		return "", err
	}
	return parsed.String(), nil
}

// Zone validates an IANA timezone identifier for a fixture.
//
// Offsets and abbreviations are not timezones: only an IANA id survives a
// daylight-saving boundary, so the harness refuses everything else.
func Zone(value string) (string, error) {
	parsed, err := coreutils.ParseIanaTimezone(value)
	if err != nil {
		return "", err
	}
	return parsed.String(), nil
}

// Directory returns a filesystem-safe fixture directory under root, derived
// from name.
//
// The slug comes from the core-utils sibling so a fixture directory, a resource
// name, and a Kubernetes object all agree on what a slug is.
func Directory(root string, name string) string {
	slug := coreutils.Slugify(name)
	if slug == "" {
		return root
	}
	return strings.TrimSuffix(root, "/") + "/" + slug
}
