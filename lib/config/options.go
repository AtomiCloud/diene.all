package config

import (
	"path/filepath"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// BaseLandscape is the sentinel landscape that applies no overlay: the base
// defaults are used as-is. An empty resolved landscape behaves the same way.
const BaseLandscape = "base"

// defaultOverlayPrefix is the basename prefix file-mode overlays resolve under,
// producing settings.<landscape>.yaml next to the base settings.yaml.
const defaultOverlayPrefix = "settings"

// Option configures a [Loader]. Options are applied in order by [NewLoader].
type Option func(*Loader)

// WithEnvPrefix sets the required environment prefix for the env layer, e.g.
// "ATOMI_". There is no default: a loader with no prefix fails fast, so ATOMI_
// is only an example and never baked in.
func WithEnvPrefix(prefix string) Option {
	return func(loader *Loader) { loader.envPrefix = prefix }
}

// WithLandscape sets the landscape explicitly, overriding the value resolved
// from the base document's app.landscape.
func WithLandscape(landscape string) Option {
	return func(loader *Loader) { loader.landscape = landscape }
}

// WithBaseSource sets the base YAML layer carrying full defaults.
func WithBaseSource(source YAMLSource) Option {
	return func(loader *Loader) { loader.base = source }
}

// WithOverlaySource registers an explicit overlay layer for landscape, taking
// precedence over file-mode resolution. It is how in-memory and test overlays
// are supplied.
func WithOverlaySource(landscape string, source YAMLSource) Option {
	return func(loader *Loader) { loader.overlays[landscape] = source }
}

// WithBaseDir configures file-mode layering rooted at dir: the base reads
// dir/settings.yaml and each landscape overlay reads dir/settings.<landscape>.yaml
// when present.
func WithBaseDir(dir string) Option {
	return func(loader *Loader) {
		loader.base = NewFileYAMLSource("base", filepath.Join(dir, defaultOverlayPrefix+".yaml"))
		loader.overlayDir = dir
	}
}

// WithEnvSource overrides the env layer source. The default reads the live
// process environment.
func WithEnvSource(source EnvSource) Option {
	return func(loader *Loader) { loader.env = source }
}

// WithSchema sets the required schema the fully merged tree is validated
// against. It is mandatory: [Loader.Load] fails fast when no schema is
// configured, so startup validation can never be silently skipped.
func WithSchema(schema Schema) Option {
	return func(loader *Loader) {
		loader.schema = schema
		loader.hasSchema = true
	}
}

// WithErrorPortal sets the service-tree portal validation problems mint their
// type URI from. The default is the client-local portal.
func WithErrorPortal(portal problem.ErrorPortal) Option {
	return func(loader *Loader) { loader.portal = portal }
}
