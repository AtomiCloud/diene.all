package appconfig

import (
	"context"
	"path/filepath"

	"github.com/AtomiCloud/diene.go-config/lib/config"
)

const EnvironmentPrefix = "ATOMI_"

// LoadOptions selects the repository-rooted config directory and optional overlay.
type LoadOptions struct {
	Landscape string
	Sources   LoadSources
}

// LoadSources supplies injectable configuration layers for black-box tests and
// non-filesystem hosts.
type LoadSources struct {
	Base        config.YAMLSource
	Overlays    map[string]config.YAMLSource
	Environment config.EnvSource
}

// Load reads base, sparse landscape overlay, and environment in that order.
func Load(ctx context.Context, options LoadOptions) (ApplicationConfig, error) {
	return LoadFromSources(ctx, options.Landscape, options.Sources)
}

// FileSources constructs the production file and environment layers without
// reading them. The caller remains responsible for resolving directory against
// the repository root.
func FileSources(configDirectory, landscape string, environ map[string]string) LoadSources {
	overlayNames := map[string]struct{}{"lapras": {}, "pichu": {}}
	if landscape != "" {
		overlayNames[landscape] = struct{}{}
	}
	overlays := make(map[string]config.YAMLSource, len(overlayNames))
	for name := range overlayNames {
		overlays[name] = config.NewOptionalFileYAMLSource(
			"overlay:"+name,
			filepath.Join(configDirectory, name+".settings.yaml"),
		)
	}
	environmentSource := config.EnvSource(config.NewOSEnvSource())
	if environ != nil {
		environmentSource = config.NewMapEnvSource("environment", environ)
	}
	return LoadSources{
		Base: config.NewFileYAMLSource(
			"base",
			filepath.Join(configDirectory, "settings.yaml"),
		),
		Overlays:    overlays,
		Environment: environmentSource,
	}
}

// LoadFromSources loads injected layers and validates the final merged tree once.
func LoadFromSources(ctx context.Context, landscape string, sources LoadSources) (ApplicationConfig, error) {
	return LoadFromSourcesWith(ctx, landscape, sources, config.FragmentFromType)
}

// LoadFromSourcesWith loads injected layers using an injectable schema reflector.
func LoadFromSourcesWith(
	ctx context.Context,
	landscape string,
	sources LoadSources,
	fragment Fragmenter,
) (ApplicationConfig, error) {
	schema, err := SchemaWith(fragment)
	if err != nil {
		return ApplicationConfig{}, err
	}
	loaderOptions := []config.Option{
		config.WithEnvPrefix(EnvironmentPrefix),
		config.WithBaseSource(sources.Base),
		config.WithEnvSource(sources.Environment),
		config.WithSchema(schema),
	}
	if landscape != "" {
		loaderOptions = append(loaderOptions, config.WithLandscape(landscape))
	}
	for name, source := range sources.Overlays {
		loaderOptions = append(loaderOptions, config.WithOverlaySource(name, source))
	}
	cfg, err := config.NewLoader(loaderOptions...).Load(ctx)
	if err != nil {
		return ApplicationConfig{}, err
	}
	return Decode(cfg)
}
