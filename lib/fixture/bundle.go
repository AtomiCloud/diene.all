package fixture

import (
	"context"
	"fmt"
	"path"
	"slices"
	"strconv"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"gopkg.in/yaml.v3"
)

// DefaultEnvPrefix is the environment prefix a fixture emits when the caller
// names none. The prefix is CONFIGURABLE per app — the config lib bakes no
// default — and this is the harness's example value, not a family constant.
const DefaultEnvPrefix = "ATOMI_"

// PathSeparator is the character that separates path segments in a fixture key.
const PathSeparator = "."

// EnvSeparator is the C0 nesting separator in an environment variable name.
const EnvSeparator = "__"

// Bundle is a built three-layer fixture: the full base document, the sparse
// landscape overlays, and the environment layer that lands last.
type Bundle struct {
	// Base is the full-defaults layer.
	Base map[string]any
	// Overlays are sparse per-landscape layers keyed by landscape name.
	Overlays map[string]map[string]any
	// Env maps dotted configuration paths onto their environment values.
	Env map[string]string
	// Lists maps dotted configuration paths onto collections rendered as C0
	// indexed environment keys.
	Lists map[string][]string
}

// Landscapes returns the overlay landscapes in stable order.
func (b Bundle) Landscapes() []string {
	names := make([]string, 0, len(b.Overlays))
	for name := range b.Overlays {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// Merged returns the base document deep-merged with one landscape overlay.
//
// The merge is the core-utils sibling's, not a second implementation here:
// a fixture that merged differently from the runtime would prove the wrong
// thing. An unknown landscape yields the base document unchanged, which is what
// "sparse overlay" means.
func (b Bundle) Merged(landscape string) map[string]any {
	overlay, found := b.Overlays[landscape]
	if !found {
		return coreutils.DeepMergeAll(b.Base)
	}
	return coreutils.DeepMergeAll(b.Base, overlay)
}

// Document renders one layer as YAML: the base document for
// [config.BaseLandscape], and the sparse overlay for any other landscape.
//
// A landscape with no overlay renders an empty document rather than failing —
// an absent overlay is a legitimate R14 state, and the loader treats a missing
// optional layer the same way.
func (b Bundle) Document(landscape string) ([]byte, error) {
	if landscape == config.BaseLandscape {
		return renderYAML(b.Base)
	}
	overlay, found := b.Overlays[landscape]
	if !found {
		return renderYAML(map[string]any{})
	}
	return renderYAML(overlay)
}

// UnrenderableError reports a fixture value YAML cannot represent.
//
// It exists because the YAML encoder PANICS on a value it does not understand —
// a func, a channel — rather than returning an error. In a test harness that is
// the worst possible behaviour: one bad fixture value would take down the whole
// test binary and report as an unrelated crash, so the panic is converted into
// an ordinary error the fixture layer can describe as a problem.
type UnrenderableError struct {
	// Reason is what the encoder objected to.
	Reason string
}

// Error renders the refusal.
func (e *UnrenderableError) Error() string {
	return "fixture: the layer cannot be rendered as YAML: " + e.Reason
}

// renderYAML marshals one layer, converting the encoder's panic into an error.
func renderYAML(layer map[string]any) (document []byte, err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			document = nil
			err = &UnrenderableError{Reason: fmt.Sprint(recovered)}
		}
	}()
	return yaml.Marshal(layer)
}

// Environ renders the environment layer with prefix, in the exact C0 shape.
//
// Scalars become `PREFIX_PATH__SEGMENT`. Collections become INDEXED keys —
// `PREFIX_PATH__0`, `PREFIX_PATH__1` — which is the whole point: no
// JSON-in-env, no comma encoding, and an empty collection emits nothing rather
// than an empty string that a loader would read as a one-element list.
func (b Bundle) Environ(prefix string) map[string]string {
	if prefix == "" {
		prefix = DefaultEnvPrefix
	}
	environ := make(map[string]string, len(b.Env)+len(b.Lists))
	for key, value := range b.Env {
		environ[EnvKey(prefix, key)] = value
	}
	for key, values := range b.Lists {
		for index, value := range values {
			environ[EnvKey(prefix, key)+EnvSeparator+strconv.Itoa(index)] = value
		}
	}
	return environ
}

// EnvKey renders one dotted configuration path as its C0 environment variable
// name.
//
// It is exported because a consumer asserting "the artifact read THIS variable"
// needs the same encoding the fixture used, and re-deriving it by hand is how
// the encoding drifts.
func EnvKey(prefix string, key string) string {
	segments := strings.Split(key, PathSeparator)
	return prefix + strings.ToUpper(strings.Join(segments, EnvSeparator))
}

// Layout records where a materialized fixture landed on disk.
type Layout struct {
	// Directory is the root the fixture was written into.
	Directory string
	// BasePath is the full-defaults document.
	BasePath string
	// OverlayPaths are the sparse landscape documents, keyed by landscape.
	OverlayPaths map[string]string
}

// Materialize writes the fixture into directory through the filesystem seam and
// returns where each layer landed.
//
// It writes through [interfaces.Vfs] rather than os so the harness's own tests
// run against the interfaces sibling's in-memory filesystem, and so a consumer
// can materialize a fixture into whatever the system under test actually reads.
func (b Bundle) Materialize(
	ctx context.Context,
	filesystem interfaces.Vfs,
	directory string,
	problems *e2e.Problems,
) (Layout, error) {
	if problems == nil {
		return Layout{}, errUnconfigured("problems")
	}
	if filesystem == nil {
		return Layout{}, problems.Raise(
			e2e.ProblemFixtureUnwritable,
			"materializing a fixture needs a filesystem seam",
			map[string]any{"component": "filesystem"},
		)
	}
	if strings.TrimSpace(directory) == "" {
		return Layout{}, problems.Raise(
			e2e.ProblemFixtureUnwritable,
			"materializing a fixture needs a directory",
			map[string]any{"component": "directory"},
		)
	}
	if err := filesystem.CreateDirectory(ctx, directory, interfaces.DirectoryOptions{Recursive: true}); err != nil {
		return Layout{}, problems.RaiseFrom(
			e2e.ProblemFixtureUnwritable,
			err,
			"the fixture directory could not be created",
			map[string]any{"directory": directory},
		)
	}
	layout := Layout{
		Directory:    directory,
		BasePath:     path.Join(directory, config.BaseLandscape+".yaml"),
		OverlayPaths: make(map[string]string, len(b.Overlays)),
	}
	if err := b.write(ctx, filesystem, problems, layout.BasePath, config.BaseLandscape); err != nil {
		return Layout{}, err
	}
	for _, landscape := range b.Landscapes() {
		target := path.Join(directory, landscape+".yaml")
		if err := b.write(ctx, filesystem, problems, target, landscape); err != nil {
			return Layout{}, err
		}
		layout.OverlayPaths[landscape] = target
	}
	return layout, nil
}

// write renders one layer and puts it on the filesystem seam.
func (b Bundle) write(
	ctx context.Context,
	filesystem interfaces.Vfs,
	problems *e2e.Problems,
	target string,
	landscape string,
) error {
	document, err := b.Document(landscape)
	if err != nil {
		return problems.RaiseFrom(
			e2e.ProblemFixtureInvalid,
			err,
			"the fixture layer could not be rendered as YAML",
			map[string]any{"landscape": landscape},
		)
	}
	options := interfaces.WriteOptions{CreateParents: true}
	if err := filesystem.WriteBytes(ctx, target, document, options); err != nil {
		return problems.RaiseFrom(
			e2e.ProblemFixtureUnwritable,
			err,
			"the fixture layer could not be written",
			map[string]any{"landscape": landscape, "path": target},
		)
	}
	return nil
}

// LoaderOptions configures [Bundle.Loader].
type LoaderOptions struct {
	// Layout is a materialized fixture; blank paths fall back to in-memory
	// sources built from the bundle itself.
	Layout Layout
	// Landscape selects the overlay to apply.
	Landscape string
	// Schema is the composed root schema the merged document is validated
	// against.
	Schema config.Schema
	// EnvPrefix is the environment prefix. Blank uses [DefaultEnvPrefix].
	EnvPrefix string
}

// Loader builds a config loader over this fixture: base, one landscape overlay,
// and the environment layer last.
//
// It reads the MATERIALIZED files when a layout is supplied, so what the loader
// validates is byte-for-byte what a compiled artifact would read. With no
// layout it falls back to in-memory sources, which is what an in-process driver
// wants.
//
// Validation itself belongs to the config lib — this function composes sources
// and hands them over; it never merges or validates anything itself.
func (b Bundle) Loader(options LoaderOptions) (*config.Loader, error) {
	baseDocument, err := b.Document(config.BaseLandscape)
	if err != nil {
		return nil, err
	}
	overlayDocument, err := b.Document(options.Landscape)
	if err != nil {
		return nil, err
	}
	prefix := options.EnvPrefix
	if prefix == "" {
		prefix = DefaultEnvPrefix
	}
	baseSource := config.YAMLSource(config.NewBytesYAMLSource(config.BaseLandscape, baseDocument))
	if options.Layout.BasePath != "" {
		baseSource = config.NewFileYAMLSource(config.BaseLandscape, options.Layout.BasePath)
	}
	overlaySource := config.YAMLSource(config.NewBytesYAMLSource(options.Landscape, overlayDocument))
	if target, found := options.Layout.OverlayPaths[options.Landscape]; found {
		overlaySource = config.NewFileYAMLSource(options.Landscape, target)
	}
	return config.NewLoader(
		config.WithEnvPrefix(prefix),
		config.WithSchema(options.Schema),
		config.WithLandscape(options.Landscape),
		config.WithBaseSource(baseSource),
		config.WithOverlaySource(options.Landscape, overlaySource),
		config.WithEnvSource(config.NewMapEnvSource("fixture", b.Environ(prefix))),
	), nil
}
