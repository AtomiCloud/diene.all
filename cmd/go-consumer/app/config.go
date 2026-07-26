package app

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-consumer/lib/appconfig"
)

const repositoryRootEnvironment = "GO_CONSUMER_ROOT"

func repositoryRoot(invocation Invocation) (string, error) {
	if configured := strings.TrimSpace(invocation.Env[repositoryRootEnvironment]); configured != "" {
		return validateRepositoryRoot(configured)
	}
	start := strings.TrimSpace(invocation.WorkingDirectory)
	if start == "" {
		current, err := os.Getwd()
		if err != nil {
			return "", fmt.Errorf("application: resolve current directory: %w", err)
		}
		start = current
	}
	absolute, err := filepath.Abs(start)
	if err != nil {
		return "", fmt.Errorf("application: resolve invocation directory: %w", err)
	}
	for candidate := filepath.Clean(absolute); ; candidate = filepath.Dir(candidate) {
		if rootErr := requireRegularFile(filepath.Join(candidate, "config", "settings.yaml")); rootErr == nil {
			return candidate, nil
		}
		parent := filepath.Dir(candidate)
		if parent == candidate {
			break
		}
	}
	return "", fmt.Errorf(
		"application: repository root not found from %q; set %s",
		start,
		repositoryRootEnvironment,
	)
}

func validateRepositoryRoot(value string) (string, error) {
	absolute, err := filepath.Abs(value)
	if err != nil {
		return "", fmt.Errorf("application: resolve repository root: %w", err)
	}
	root := filepath.Clean(absolute)
	if err := requireRegularFile(filepath.Join(root, "config", "settings.yaml")); err != nil {
		return "", fmt.Errorf("application: invalid repository root %q: %w", root, err)
	}
	return root, nil
}

func requireRegularFile(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return errors.New("subject is not a regular file")
	}
	return nil
}

func loadApplicationConfig(
	ctx context.Context,
	root string,
	landscape string,
	environment map[string]string,
) (appconfig.ApplicationConfig, error) {
	configDirectory := filepath.Join(root, "config")
	overlayPaths, err := filepath.Glob(filepath.Join(configDirectory, "*.settings.yaml"))
	if err != nil {
		return appconfig.ApplicationConfig{}, fmt.Errorf("application: discover config overlays: %w", err)
	}
	overlays := make(map[string]config.YAMLSource, len(overlayPaths))
	for _, overlayPath := range overlayPaths {
		filename := filepath.Base(overlayPath)
		name := strings.TrimSuffix(filename, ".settings.yaml")
		if name == "" {
			return appconfig.ApplicationConfig{}, fmt.Errorf("application: invalid config overlay %q", filename)
		}
		overlays[name] = config.NewFileYAMLSource("overlay:"+name, overlayPath)
	}
	loaded, err := appconfig.Load(ctx, appconfig.LoadOptions{
		Landscape: landscape,
		Sources: appconfig.LoadSources{
			Base:        config.NewFileYAMLSource("base", filepath.Join(configDirectory, "settings.yaml")),
			Overlays:    overlays,
			Environment: config.NewMapEnvSource("invocation-environment", environment),
		},
	})
	if err != nil {
		return appconfig.ApplicationConfig{}, fmt.Errorf("application: load configuration: %w", err)
	}
	return loaded, nil
}

func rootedPath(root string, configured string) (string, error) {
	value := strings.TrimSpace(configured)
	if value == "" {
		return "", errors.New("application: configured path is blank")
	}
	if filepath.IsAbs(value) {
		return filepath.Clean(value), nil
	}
	resolved := filepath.Clean(filepath.Join(root, value))
	relative, err := filepath.Rel(root, resolved)
	if err != nil {
		return "", fmt.Errorf("application: resolve path %q: %w", configured, err)
	}
	if relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("application: path %q escapes repository root", configured)
	}
	return resolved, nil
}
