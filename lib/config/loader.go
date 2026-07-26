package config

import (
	"context"
	"errors"
	"fmt"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/collision"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/layers"
	"github.com/AtomiCloud/diene.go-config/lib/config/internal/nilguard"
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
	hasPortal  bool
}

// NewLoader creates a loader with the process-environment source as the env
// layer. Supply the required [WithEnvPrefix], a base via [WithBaseSource] or
// [WithBaseDir], and a schema via [WithSchema]; [Loader.Load] fails fast when
// any of the three is missing. A nil [Option] is ignored.
func NewLoader(options ...Option) *Loader {
	loader := &Loader{
		overlays: map[string]YAMLSource{},
		env:      NewOSEnvSource(),
	}
	for _, option := range options {
		if option != nil {
			option(loader)
		}
	}
	return loader
}

// Load reads, merges, validates, and returns the configuration. The base YAML
// full defaults are overlaid by the resolved landscape's sparse overlay, and
// the environment is folded on LAST. Layers merge with the core-utils canonical
// rule, so a value spelled in any of snake, kebab, camel, or Pascal in one layer
// overrides the same logical key in another. Every layer is rejected if two
// sibling keys share a canonical form, so resolution never depends on map
// iteration order. The fully merged tree is validated exactly once against the
// required schema; problems mint their type URI from the schema's portal, or
// from [WithErrorPortal] when one is set. An invalid tree fails fast.
func (l *Loader) Load(ctx context.Context) (*Config, error) {
	if l.envPrefix == "" {
		return nil, errors.New("config: an environment prefix is required (WithEnvPrefix); ATOMI_ is only an example")
	}
	if nilguard.IsNil(l.base) {
		return nil, errors.New("config: a base source is required (WithBaseSource or WithBaseDir)")
	}
	if nilguard.IsNil(l.env) {
		return nil, errors.New("config: the environment source must not be nil (WithEnvSource)")
	}
	if !l.hasSchema {
		return nil, errors.New("config: a schema is required (WithSchema); Load validates the final merged tree")
	}

	portal := l.portal
	if !l.hasPortal {
		portal = l.schema.portal
	}

	baseContent, err := l.base.Read(ctx)
	if err != nil {
		return nil, valid.Problem(portal, []valid.Issue{{Path: l.base.Name(), Message: err.Error()}})
	}
	// Detect canonical collisions on the raw bytes before Viper can collapse
	// case-only aliases, then parse with Viper.
	if location, message, collided := collision.DetectYAML(baseContent); collided {
		return nil, valid.Problem(portal, []valid.Issue{{Path: location, Message: message}})
	}
	baseViper, err := layers.BaseViper(baseContent)
	if err != nil {
		return nil, valid.Problem(portal, []valid.Issue{{Path: l.base.Name(), Message: err.Error()}})
	}

	// Resolve, token-check, and fold the sparse overlay for the landscape onto
	// the base Viper. This is bounded per-loader wiring over the layers package;
	// the base sentinel and the empty landscape apply none.
	landscape := layers.ResolveLandscape(baseViper.AllSettings(), l.landscape)
	if landscape != "" && landscape != BaseLandscape {
		overlaySource, ok := l.overlays[landscape]
		switch {
		case ok:
			// Registered overlay: validate the landscape token grammar on its own.
			if err = layers.ValidateLandscape(landscape); err != nil {
				return nil, valid.Problem(portal, []valid.Issue{{Path: AppKey + ".landscape", Message: err.Error()}})
			}
		case l.overlayDir != "":
			// File mode: OverlayPath validates the token grammar and containment.
			path, pathErr := layers.OverlayPath(l.overlayDir, landscape)
			if pathErr != nil {
				return nil, valid.Problem(portal, []valid.Issue{{Path: AppKey + ".landscape", Message: pathErr.Error()}})
			}
			overlaySource = NewOptionalFileYAMLSource("overlay:"+landscape, path)
			ok = true
		default:
			// No overlay configured; still reject a malicious landscape token.
			if err = layers.ValidateLandscape(landscape); err != nil {
				return nil, valid.Problem(portal, []valid.Issue{{Path: AppKey + ".landscape", Message: err.Error()}})
			}
		}
		if ok {
			if nilguard.IsNil(overlaySource) {
				return nil, valid.Problem(portal, []valid.Issue{{Path: AppKey + ".landscape", Message: fmt.Sprintf("overlay source for landscape %q is nil", landscape)}})
			}
			content, readErr := overlaySource.Read(ctx)
			if readErr != nil {
				return nil, valid.Problem(portal, []valid.Issue{{Path: overlaySource.Name(), Message: readErr.Error()}})
			}
			if content != nil {
				if location, message, collided := collision.DetectYAML(content); collided {
					return nil, valid.Problem(portal, []valid.Issue{{Path: location, Message: message}})
				}
				overlayViper, parseErr := layers.BaseViper(content)
				if parseErr != nil {
					return nil, valid.Problem(portal, []valid.Issue{{Path: overlaySource.Name(), Message: parseErr.Error()}})
				}
				layers.Merge(baseViper, overlayViper.AllSettings())
			}
		}
	}

	environment, err := l.env.Environ(ctx)
	if err != nil {
		return nil, valid.Problem(portal, []valid.Issue{{Path: l.env.Name(), Message: err.Error()}})
	}
	envSettings, err := coreutils.EnvironmentToNestedMap(environment, l.envPrefix)
	if err != nil {
		return nil, valid.Problem(portal, []valid.Issue{valid.EnvIssue(err)})
	}
	if location, message, collided := collision.Detect(envSettings); collided {
		return nil, valid.Problem(portal, []valid.Issue{{Path: location, Message: message}})
	}

	// The environment layer is folded on LAST with the canonical deep merge, so
	// an env value overrides the merged YAML key it matches across spellings.
	merged := coreutils.DeepMerge(baseViper.AllSettings(), envSettings)
	if err = valid.Evaluate(l.schema.root, portal, merged); err != nil {
		return nil, err
	}
	return NewConfig(merged), nil
}
