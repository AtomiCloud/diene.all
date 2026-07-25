package config

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/spf13/viper"
)

// Loader assembles a validated [Config] from a base YAML layer, an optional
// per-landscape overlay, and the process environment applied last. Construct it
// with [NewLoader] and one or more [Option] values.
type Loader struct {
	envPrefix  string
	landscape  string
	base       YAMLSource
	overlays   map[string]YAMLSource
	overlayDir string
	env        EnvSource
	schema     Schema
	hasSchema  bool
	portal     problem.ErrorPortal
}

// NewLoader creates a loader with the process-environment source as the env
// layer and no base, overlay, or schema. Supply the required [WithEnvPrefix]
// and a base via [WithBaseSource] or [WithBaseDir].
func NewLoader(options ...Option) *Loader {
	loader := &Loader{
		overlays: map[string]YAMLSource{},
		env:      NewOSEnvSource(),
	}
	for _, option := range options {
		option(loader)
	}
	return loader
}

// Load reads, merges, validates, and returns the configuration. The base YAML
// full defaults are overlaid by the resolved landscape's sparse overlay, and
// the environment is folded on LAST. When a schema is configured the fully
// merged tree is validated exactly once; an invalid final tree fails fast with
// a problem-typed error.
func (l *Loader) Load(ctx context.Context) (*Config, error) {
	if l.envPrefix == "" {
		return nil, errors.New("config: an environment prefix is required (WithEnvPrefix); ATOMI_ is only an example")
	}
	if l.base == nil {
		return nil, errors.New("config: a base source is required (WithBaseSource or WithBaseDir)")
	}

	baseViper, err := l.readLayer(ctx, l.base)
	if err != nil {
		return nil, err
	}

	landscape := l.resolveLandscape(baseViper)
	if overlay, ok := l.overlayFor(landscape); ok {
		if err = l.mergeOverlay(ctx, baseViper, overlay); err != nil {
			return nil, err
		}
	}

	environment, err := l.env.Environ(ctx)
	if err != nil {
		return nil, fmt.Errorf("config: read env layer %q: %w", l.env.Name(), err)
	}
	envLayer, err := coreutils.EnvironmentToNestedMap(environment, l.envPrefix)
	if err != nil {
		return nil, l.envProblem(err)
	}

	merged := coreutils.DeepMerge(baseViper.AllSettings(), envLayer)

	if l.hasSchema {
		if err := l.schema.WithPortal(l.portalOrLocal()).Validate(merged); err != nil {
			return nil, err
		}
	}
	return NewConfig(merged), nil
}

// readLayer reads a YAML source into a fresh viper instance seeded with the tin
// loader shape (yaml type plus an env-key replacer).
func (l *Loader) readLayer(ctx context.Context, source YAMLSource) (*viper.Viper, error) {
	content, err := source.Read(ctx)
	if err != nil {
		return nil, fmt.Errorf("config: read layer %q: %w", source.Name(), err)
	}
	layer := newYAMLViper()
	if err := layer.ReadConfig(bytes.NewReader(content)); err != nil {
		return nil, l.yamlProblem(source.Name(), err)
	}
	return layer, nil
}

// mergeOverlay reads the overlay into a second viper and folds it onto the base
// via MergeConfigMap. An absent optional overlay is a no-op.
func (l *Loader) mergeOverlay(ctx context.Context, base *viper.Viper, overlay YAMLSource) error {
	content, err := overlay.Read(ctx)
	if err != nil {
		return fmt.Errorf("config: read overlay %q: %w", overlay.Name(), err)
	}
	if content == nil {
		return nil
	}
	overlayViper := newYAMLViper()
	if err := overlayViper.ReadConfig(bytes.NewReader(content)); err != nil {
		return l.yamlProblem(overlay.Name(), err)
	}
	// MergeConfigMap only ever returns nil in viper; the overlay is folded on.
	_ = base.MergeConfigMap(overlayViper.AllSettings())
	return nil
}

// resolveLandscape returns the explicit landscape when set, otherwise the base
// document's app.landscape.
func (l *Loader) resolveLandscape(base *viper.Viper) string {
	if l.landscape != "" {
		return l.landscape
	}
	return base.GetString(AppKey + ".landscape")
}

// overlayFor resolves the overlay source for landscape: the base sentinel and
// the empty landscape apply none, an explicit registration wins, and file mode
// resolves settings.<landscape>.yaml under the base dir.
func (l *Loader) overlayFor(landscape string) (YAMLSource, bool) {
	if landscape == "" || landscape == BaseLandscape {
		return nil, false
	}
	if source, ok := l.overlays[landscape]; ok {
		return source, true
	}
	if l.overlayDir != "" {
		path := filepath.Join(l.overlayDir, defaultOverlayPrefix+"."+landscape+".yaml")
		return NewOptionalFileYAMLSource("overlay:"+landscape, path), true
	}
	return nil, false
}

// portalOrLocal returns the configured portal, defaulting to the client-local
// portal.
func (l *Loader) portalOrLocal() problem.ErrorPortal {
	if l.portal.Host == "" {
		return problem.LocalErrorPortal()
	}
	return l.portal
}

// yamlProblem reports a malformed YAML layer as a problem-typed validation
// failure keyed by the layer name.
func (l *Loader) yamlProblem(layer string, cause error) error {
	return newValidationProblem(l.portalOrLocal(), []Issue{{Path: layer, Message: cause.Error()}})
}

// envProblem reports an environment coercion failure as a problem-typed
// validation failure, preserving the offending key and reason.
func (l *Loader) envProblem(cause error) error {
	issue := Issue{Path: "(environment)", Message: cause.Error()}
	var coercion *coreutils.EnvironmentCoercionError
	if errors.As(cause, &coercion) {
		issue = Issue{Path: coercion.Key, Message: coercion.Reason}
	}
	return newValidationProblem(l.portalOrLocal(), []Issue{issue})
}

// newYAMLViper builds a viper seeded with the tin loader shape: YAML config
// type plus an env-key replacer. The env layer itself is produced by core-utils
// rather than viper's AutomaticEnv, so lists arrive as indexed keys.
func newYAMLViper() *viper.Viper {
	instance := viper.New()
	instance.SetConfigType("yaml")
	instance.SetEnvKeyReplacer(strings.NewReplacer("-", "_", ".", "__"))
	return instance
}
