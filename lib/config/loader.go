package config

import (
	"context"
	"errors"
	"fmt"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/layers"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/valid"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
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
// layer. Supply the required [WithEnvPrefix], a base via [WithBaseSource] or
// [WithBaseDir], and a schema via [WithSchema]; [Loader.Load] fails fast when
// any of the three is missing.
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
// the environment is folded on LAST. Layers merge with the core-utils canonical
// rule, so a value spelled in any of snake, kebab, camel, or Pascal in one layer
// overrides the same logical key in another. The fully merged tree is validated
// exactly once against the required schema; an invalid tree fails fast with a
// problem-typed error.
func (l *Loader) Load(ctx context.Context) (*Config, error) {
	if l.envPrefix == "" {
		return nil, errors.New("config: an environment prefix is required (WithEnvPrefix); ATOMI_ is only an example")
	}
	if l.base == nil {
		return nil, errors.New("config: a base source is required (WithBaseSource or WithBaseDir)")
	}
	if !l.hasSchema {
		return nil, errors.New("config: a schema is required (WithSchema); Load validates the final merged tree")
	}

	baseContent, err := l.base.Read(ctx)
	if err != nil {
		return nil, fmt.Errorf("config: read layer %q: %w", l.base.Name(), err)
	}
	baseViper, err := layers.BaseViper(baseContent)
	if err != nil {
		return nil, valid.Problem(l.portal, []valid.Issue{{Path: l.base.Name(), Message: err.Error()}})
	}

	// Resolve, token-check, and fold the sparse overlay for the landscape onto
	// the base Viper with MergeConfigMap. This is bounded per-loader wiring over
	// the layers package; the base sentinel and the empty landscape apply none.
	landscape := layers.ResolveLandscape(baseViper.AllSettings(), l.landscape)
	if landscape != "" && landscape != BaseLandscape {
		overlaySource, ok := l.overlays[landscape]
		switch {
		case ok:
			// Registered overlay: validate the landscape token grammar on its own.
			if err = layers.ValidateLandscape(landscape); err != nil {
				return nil, valid.Problem(l.portal, []valid.Issue{{Path: AppKey + ".landscape", Message: err.Error()}})
			}
		case l.overlayDir != "":
			// File mode: OverlayPath validates the token grammar and containment.
			path, pathErr := layers.OverlayPath(l.overlayDir, landscape)
			if pathErr != nil {
				return nil, valid.Problem(l.portal, []valid.Issue{{Path: AppKey + ".landscape", Message: pathErr.Error()}})
			}
			overlaySource = NewOptionalFileYAMLSource("overlay:"+landscape, path)
			ok = true
		default:
			// No overlay configured; still reject a malicious landscape token.
			if err = layers.ValidateLandscape(landscape); err != nil {
				return nil, valid.Problem(l.portal, []valid.Issue{{Path: AppKey + ".landscape", Message: err.Error()}})
			}
		}
		if ok {
			content, readErr := overlaySource.Read(ctx)
			if readErr != nil {
				return nil, fmt.Errorf("config: read overlay %q: %w", overlaySource.Name(), readErr)
			}
			if content != nil {
				if err = layers.MergeOverlay(baseViper, content); err != nil {
					return nil, valid.Problem(l.portal, []valid.Issue{{Path: overlaySource.Name(), Message: err.Error()}})
				}
			}
		}
	}

	environment, err := l.env.Environ(ctx)
	if err != nil {
		return nil, fmt.Errorf("config: read env layer %q: %w", l.env.Name(), err)
	}
	envSettings, err := coreutils.EnvironmentToNestedMap(environment, l.envPrefix)
	if err != nil {
		return nil, valid.Problem(l.portal, []valid.Issue{valid.EnvIssue(err)})
	}

	// The environment layer is folded on LAST with the canonical deep merge, so
	// an env value overrides the merged YAML key it matches across spellings.
	merged := coreutils.DeepMerge(baseViper.AllSettings(), envSettings)
	if err = valid.Evaluate(l.schema.root, l.portal, merged); err != nil {
		return nil, err
	}
	return NewConfig(merged), nil
}
